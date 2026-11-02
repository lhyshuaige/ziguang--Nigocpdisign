"""Frozen UltraFace asset validation, image preparation and result evidence.

This module does not perform inference. Boxes must come from the board.
"""
import hashlib
import json
import struct
import time
import zlib
from pathlib import Path

from PIL import Image, ImageDraw, ImageOps

MODEL_BYTES = 1371584
MODEL_CRC32 = 0x576c738f
MODEL_SHA256 = '569f94b78e7088348ce4f4c693584757bef516a284007884d3e74d540fd506cf'
FRAME_SIZE = (320, 240)


def validate_model(blob):
    """Match the ABI and frozen asset accepted by uf_bind in packaged firmware."""
    if len(blob) != MODEL_BYTES:
        raise ValueError('当前 UltraFace 固件要求配套冻结模型（1,371,584 字节）；请使用 assets/model/ultraface.ngm')
    header = struct.unpack_from('<16I', blob)
    if header[:6] != (0x314d474e, 1, MODEL_BYTES, 42, 64, 4096):
        raise ValueError('模型 NGM1 头或层布局与当前固件不兼容')
    checksum = zlib.crc32(blob)
    digest = hashlib.sha256(blob).hexdigest()
    if checksum != MODEL_CRC32 or digest != MODEL_SHA256:
        raise ValueError('模型校验失败：文件损坏或不是当前固件支持的冻结模型')
    return dict(name='UltraFace-Slim-320', model_bytes=len(blob), crc32='%08x' % checksum,
                sha256=digest, layers=42, jobs=7360, input='320x240 RGB888',
                confidence_threshold=.7, nms_iou_threshold=.3)


def load_original(path):
    """Keep decoded full-resolution RGB pixels in their displayed EXIF orientation."""
    with Image.open(path) as image:
        return ImageOps.exif_transpose(image).convert('RGB')


def prepare_image(path):
    """Preserve the validated direct-resize pixels sent to the board."""
    return load_original(path).resize(FRAME_SIZE, Image.Resampling.BILINEAR)


def map_boxes(boxes, target_size):
    """Map 320x240 edge coordinates to a direct-resize source or preview canvas."""
    width, height = target_size
    if width <= 0 or height <= 0:
        raise ValueError('target dimensions must be positive')
    mapped = []
    for box in boxes:
        item = dict(box)
        for key in ('x1', 'x2'):
            item[key] = max(0, min(FRAME_SIZE[0], box[key])) * width / FRAME_SIZE[0]
        for key in ('y1', 'y2'):
            item[key] = max(0, min(FRAME_SIZE[1], box[key])) * height / FRAME_SIZE[1]
        mapped.append(item)
    return mapped


def annotate_image(image, boxes):
    annotated = image.copy()
    draw = ImageDraw.Draw(annotated)
    stroke = max(2, round(min(image.size) / 240 * 2))
    for box in boxes:
        # NGE1 uses exclusive right/bottom edges; preserve subpixel mapping in JSON.
        left, top = round(box['x1']), round(box['y1'])
        right, bottom = max(left, round(box['x2'])-1), max(top, round(box['y2'])-1)
        draw.rectangle((left, top, right, bottom), outline='#00ff88', width=stroke)
        label = '#%d %.1f%%' % (box['track_id'], box['score']*100)
        draw.text((left+2, max(0, top-12)), label, fill='#00ff88',
                  stroke_width=1, stroke_fill='black')
    return annotated


def save_detection(directory, image, result, source='', board='', *, original_image=None):
    """Save a unique, self-contained bundle without modifying the caller's image."""
    if image.mode != 'RGB' or image.size != FRAME_SIZE:
        raise ValueError('result input must be the transmitted 320x240 RGB image')
    pixels = image.tobytes()
    digest = hashlib.sha256(pixels).hexdigest()
    if result.get('input_sha256') != digest or result.get('error'):
        raise ValueError('检测结果不属于这张输入图片，或板端返回了错误')
    original_record = {}
    if original_image is not None:
        if (original_image.mode != 'RGB' or
                original_image.resize(FRAME_SIZE, Image.Resampling.BILINEAR).tobytes() != pixels):
            raise ValueError('原图与本次送入板卡的图片不匹配')
        original_record = dict(
            original_rgb_sha256=hashlib.sha256(original_image.tobytes()).hexdigest(),
            original_size=list(original_image.size),
            original_boxes=map_boxes(result['boxes'], original_image.size),
            image_transform=dict(mode='direct_resize', input_size=list(FRAME_SIZE),
                                 source_size=list(original_image.size),
                                 scale_x=FRAME_SIZE[0]/original_image.width,
                                 scale_y=FRAME_SIZE[1]/original_image.height,
                                 offset_x=0, offset_y=0,
                                 source_orientation='EXIF-transposed'))
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    stem = 'face_%s_%08x_%d' % (time.strftime('%Y%m%d_%H%M%S'), result['frame_id'], time.time_ns())
    output = directory / stem
    output.mkdir(exist_ok=False)
    image.save(output / 'input.png')
    annotate_image(image, result['boxes']).save(output / 'annotated.png')
    if original_image is not None:
        original_image.save(output / 'original.png')
        annotate_image(original_image, original_record['original_boxes']).save(output / 'original_annotated.png')
    record = dict(result, source=source, board=board,
                  saved_at=time.strftime('%Y-%m-%dT%H:%M:%S%z'),
                  input_sha256=digest, model_expected_sha256=MODEL_SHA256,
                  inference_source='FPGA SoC NGE1 response', identity_recognition=False)
    record.update(original_record)
    (output / 'result.json').write_text(json.dumps(record, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    return str(output)
