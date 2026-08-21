import os
import sys
import time
import numpy as np
import torch
import torch.nn as nn

try:
    import onnx
    import onnxruntime as ort
    from onnxruntime.quantization import quantize_dynamic, QuantType
except ImportError:
    print("onnx and onnxruntime must be installed.")
    sys.exit(1)


class ConvBlock1D(nn.Module):
    def __init__(self, in_ch, out_ch, kernel_size=7, stride=1, dilation=1):
        super().__init__()
        padding = (kernel_size - 1) * dilation // 2
        self.conv = nn.Conv1d(in_ch, out_ch, kernel_size, stride=stride, padding=padding, dilation=dilation)
        self.norm = nn.BatchNorm1d(out_ch)
        self.act = nn.LeakyReLU(0.2)

    def forward(self, x):
        return self.act(self.norm(self.conv(x)))


class ResBlock1D(nn.Module):
    def __init__(self, channels, kernel_size=5, dilation=1):
        super().__init__()
        padding = (kernel_size - 1) * dilation // 2
        self.conv1 = nn.Conv1d(channels, channels, kernel_size, padding=padding, dilation=dilation)
        self.act1 = nn.LeakyReLU(0.2)
        self.conv2 = nn.Conv1d(channels, channels, kernel_size, padding=padding, dilation=dilation)
        self.act2 = nn.LeakyReLU(0.2)

    def forward(self, x):
        return x + self.act2(self.conv2(self.act1(self.conv1(x))))


class Lightweight2StemSeparator(nn.Module):
    def __init__(self):
        super().__init__()
        self.enc1 = ConvBlock1D(1, 32, kernel_size=15, stride=1)
        self.enc2 = nn.Sequential(
            nn.Conv1d(32, 64, kernel_size=8, stride=4, padding=2),
            nn.BatchNorm1d(64),
            nn.LeakyReLU(0.2),
        )
        self.enc3 = nn.Sequential(
            nn.Conv1d(64, 128, kernel_size=8, stride=4, padding=2),
            nn.BatchNorm1d(128),
            nn.LeakyReLU(0.2),
        )

        self.res1 = ResBlock1D(128, dilation=1)
        self.res2 = ResBlock1D(128, dilation=2)
        self.res3 = ResBlock1D(128, dilation=4)

        self.dec3 = nn.Sequential(
            nn.ConvTranspose1d(128, 64, kernel_size=8, stride=4, padding=2), # -> (B, 64, 512)
            nn.BatchNorm1d(64),
            nn.LeakyReLU(0.2),
        )
        self.dec2 = nn.Sequential(
            nn.ConvTranspose1d(64 + 64, 32, kernel_size=8, stride=4, padding=2), # -> (B, 32, 2048)
            nn.BatchNorm1d(32),
            nn.LeakyReLU(0.2),
        )

        self.out_head = nn.Conv1d(32 + 32, 2, kernel_size=15, padding=7)

        self._init_weights()

    def _init_weights(self):
        for m in self.modules():
            if isinstance(m, (nn.Conv1d, nn.ConvTranspose1d)):
                nn.init.kaiming_normal_(m.weight, mode='fan_out', nonlinearity='leaky_relu')
                if m.bias is not None:
                    nn.init.constant_(m.bias, 0.0)

    def forward(self, x):
        e1 = self.enc1(x)
        e2 = self.enc2(e1)           
        e3 = self.enc3(e2)           

        b = self.res1(e3)
        b = self.res2(b)
        b = self.res3(b)            

        d3 = self.dec3(b)         
        d2 = self.dec2(torch.cat([d3, e2], dim=1)) 

        out = self.out_head(torch.cat([d2, e1], dim=1))

        stem_weights = torch.sigmoid(out)
        vocal = x * stem_weights[:, 0:1, :]
        bgm = x * stem_weights[:, 1:2, :]

        return torch.cat([vocal, bgm], dim=1) 


def export_and_quantize(output_dir="models"):
    os.makedirs(output_dir, exist_ok=True)
    fp32_onnx_path = os.path.join(output_dir, "2stem_separator_fp32.onnx")
    int8_onnx_path = os.path.join(output_dir, "2stem_separator_int8.onnx")

    print("Initializing Lightweight 2-Stem Separation Model")
    model = Lightweight2StemSeparator()
    model.eval()

    dummy_input = torch.randn(1, 1, 2048, dtype=torch.float32)
    with torch.no_grad():
        test_out = model(dummy_input)
    print(f"PyTorch test forward pass output shape: {test_out.shape}")
    assert test_out.shape == (1, 2, 2048), f"Expected (1, 2, 2048), got {test_out.shape}"

    print(f"\n Exporting to ONNX ({fp32_onnx_path})")
    torch.onnx.export(
        model,
        dummy_input,
        fp32_onnx_path,
        export_params=True,
        opset_version=17,
        do_constant_folding=True,
        input_names=["input_audio"],
        output_names=["stems_output"],
    )

    onnx_model = onnx.load(fp32_onnx_path)
    onnx.checker.check_model(onnx_model)
    fp32_size = os.path.getsize(fp32_onnx_path) / 1024
    print(f"FP32 ONNX Model successfully exported! Size: {fp32_size:.2f} KB")

    print(f"\n Quantizing to INT8 ({int8_onnx_path}")
    quantize_dynamic(
        model_input=fp32_onnx_path,
        model_output=int8_onnx_path,
        weight_type=QuantType.QInt8,
    )
    int8_size = os.path.getsize(int8_onnx_path) / 1024
    print(f"INT8 Quantized Model saved! Size: {int8_size:.2f} KB (Reduction: {(1 - int8_size/fp32_size)*100:.1f}%)")

    print("\n Verifying Inference with ONNX Runtime ")
    session_fp32 = ort.InferenceSession(fp32_onnx_path, providers=["CPUExecutionProvider"])
    session_int8 = ort.InferenceSession(int8_onnx_path, providers=["CPUExecutionProvider"])

    np_input = np.random.randn(1, 1, 2048).astype(np.float32)


    start = time.perf_counter()
    for _ in range(100):
        ort_out_fp32 = session_fp32.run(None, {"input_audio": np_input})[0]
    fp32_time_ms = (time.perf_counter() - start) * 10.0
    start = time.perf_counter()
    for _ in range(100):
        ort_out_int8 = session_int8.run(None, {"input_audio": np_input})[0]
    int8_time_ms = (time.perf_counter() - start) * 10.0

    print(f"FP32 Output shape: {ort_out_fp32.shape}, Avg Latency: {fp32_time_ms:.3f} ms / frame")
    print(f"INT8 Output shape: {ort_out_int8.shape}, Avg Latency: {int8_time_ms:.3f} ms / frame")

    assert ort_out_fp32.shape == (1, 2, 2048)
    assert ort_out_int8.shape == (1, 2, 2048)
    print("\n Python verification complete")


if __name__ == "__main__":
    export_and_quantize()
