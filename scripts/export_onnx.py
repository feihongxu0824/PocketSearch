"""
Export MobileCLIP-S1 image and text encoders to ONNX format using Apple's mobileclip.

Usage (from project root):
    .venv/bin/python scripts/export_onnx.py

Prerequisite:
    Download checkpoint: https://docs-assets.developer.apple.com/ml-research/datasets/mobileclip/mobileclip_s1.pt
    Place at /tmp/mobileclip_s1.pt (or modify CHECKPOINT_PATH below)
    Install dependencies:
        uv pip install --python .venv/bin/python torch torchvision timm open-clip-torch onnx onnxruntime MNN
        uv pip install --python .venv/bin/python --no-deps "mobileclip @ git+https://github.com/apple/ml-mobileclip.git"

Output:
    assets/models/mobileclip_s1_image_encoder.onnx
    assets/models/mobileclip_s1_text_encoder.onnx
"""

import os
import torch
import mobileclip

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
OUTPUT_DIR = os.path.join(SCRIPT_DIR, '..', 'assets', 'models')
CHECKPOINT_PATH = '/tmp/mobileclip_s1.pt'

MODEL_NAME = 'mobileclip_s1'
CONTEXT_LENGTH = 77
IMAGE_SIZE = 256


class ImageEncoderWrapper(torch.nn.Module):
    """Wrap the CLIP model to only expose image encoding."""
    def __init__(self, model):
        super().__init__()
        self.model = model

    def forward(self, image):
        return self.model.encode_image(image)


class TextEncoderWrapper(torch.nn.Module):
    """Wrap the CLIP model to only expose text encoding."""
    def __init__(self, model):
        super().__init__()
        self.model = model

    def forward(self, text):
        return self.model.encode_text(text)


def export_image_encoder(model):
    """Export image encoder to ONNX."""
    wrapper = ImageEncoderWrapper(model)
    wrapper.eval()

    dummy_image = torch.randn(1, 3, IMAGE_SIZE, IMAGE_SIZE)
    output_path = os.path.join(OUTPUT_DIR, 'mobileclip_s1_image_encoder.onnx')

    print('  Exporting image encoder...')
    torch.onnx.export(
        wrapper,
        dummy_image,
        output_path,
        opset_version=14,
        input_names=['image'],
        output_names=['embedding'],
        dynamo=False,
    )
    size_mb = os.path.getsize(output_path) / (1024 * 1024)
    print(f'  Image encoder saved: {output_path} ({size_mb:.1f} MB)')


def export_text_encoder(model):
    """Export text encoder to ONNX."""
    wrapper = TextEncoderWrapper(model)
    wrapper.eval()

    dummy_text = torch.randint(0, 49408, (1, CONTEXT_LENGTH), dtype=torch.long)
    output_path = os.path.join(OUTPUT_DIR, 'mobileclip_s1_text_encoder.onnx')

    print('  Exporting text encoder...')
    torch.onnx.export(
        wrapper,
        dummy_text,
        output_path,
        opset_version=14,
        input_names=['text'],
        output_names=['embedding'],
        dynamo=False,
    )
    size_mb = os.path.getsize(output_path) / (1024 * 1024)
    print(f'  Text encoder saved: {output_path} ({size_mb:.1f} MB)')


def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    print(f'Loading {MODEL_NAME} from {CHECKPOINT_PATH}...')
    model, _, preprocess = mobileclip.create_model_and_transforms(
        MODEL_NAME,
        pretrained=CHECKPOINT_PATH,
        device='cpu',
    )
    model.eval()

    # Sanity check
    with torch.no_grad():
        dummy_img = torch.randn(1, 3, IMAGE_SIZE, IMAGE_SIZE)
        img_feat = model.encode_image(dummy_img)
        print(f'  Image embedding shape: {img_feat.shape}')

        tokenizer = mobileclip.get_tokenizer(MODEL_NAME)
        tokens = tokenizer(['a photo of a cat'])
        txt_feat = model.encode_text(tokens)
        print(f'  Text embedding shape: {txt_feat.shape}')

    print()
    export_image_encoder(model)
    export_text_encoder(model)
    print('\nDone!')


if __name__ == '__main__':
    main()
