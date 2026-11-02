import hashlib
import json
import socket
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from PIL import Image
from nigo_host.client import Endpoint, Host
from nigo_host.face import (validate_model, prepare_image, save_detection, MODEL_SHA256,
                            load_original, map_boxes)
from nigo_host import upload
from nigo_host.face_rpc import FaceClient, FaceRPCError, HEADER, STATUS
from test_protocols import Server, ngu_ack, result_packet

ROOT = Path(__file__).resolve().parents[1]


class FaceTests(unittest.TestCase):
    def test_dropped_result_is_retrieved_without_resubmission(self):
        frame = [0, 0]
        begins = []
        def handle(sock, data, peer, _):
            if data[:4] == b'NFC1':
                _,ver,op,seq,fid = HEADER.unpack(data)
                if op == 1:
                    values = [0]*23
                    values[0]=1; values[2]=42; values[11:13]=frame
                    values[14]=1
                    body=STATUS.pack(*values)
                else:
                    self.assertEqual(fid,frame[0])
                    body=result_packet(frame[0], stamp=frame[1])
                sock.sendto(HEADER.pack(b'NFS1',ver,op,seq,0)+body,peer)
                return
            fields = upload.HEADER.unpack_from(data)
            if fields[2] == 1: begins.append(data)
            if fields[2] == 3: frame[:] = fields[4],fields[-1]
            sock.sendto(ngu_ack(data),peer)  # Deliberately omit UDP 5002 result.
        with Server(handle) as server:
            result=Host(Endpoint('127.0.0.1','127.0.0.1'),server.port(),result_port=0).detect(bytes(230400),result_timeout=2)
        self.assertEqual(result['result_transport'],'retained RPC')
        self.assertEqual(len(begins),1)
        self.assertEqual(len(result['boxes']),1)

    def test_rpc_stale_reply_and_result_owner_error(self):
        def handle(sock,data,peer,_):
            _,version,op,seq,fid=HEADER.unpack(data)
            sock.sendto(HEADER.pack(b'NFS1',version,op,seq^1,0)+STATUS.pack(*([0]*23)),peer)
            sock.sendto(HEADER.pack(b'NFS1',version,op,seq,3),peer)
        with Server(handle) as server:
            client=FaceClient(Endpoint('127.0.0.1','127.0.0.1'),server.port())
            try:
                with self.assertRaises(FaceRPCError) as caught:client.call(2,99)
                self.assertEqual(caught.exception.code,3)
            finally:client.close()

    def test_frozen_model_and_corruption_before_network(self):
        model = (ROOT/'assets/model/ultraface.ngm').read_bytes()
        self.assertEqual(validate_model(model)['sha256'], MODEL_SHA256)
        damaged = bytearray(model)
        damaged[-1] ^= 1
        for blob in (b'ONNX', model[:-1], damaged):
            with patch('nigo_host.client.Uploader', side_effect=AssertionError('network opened')):
                with self.assertRaises(ValueError):
                    Host(Endpoint()).model(blob)

    def test_photo_orientation_and_rgb(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'rotated.png'
            image = Image.new('RGB', (40, 20), 'red')
            image.paste('blue', (20, 0, 40, 20))
            exif = image.getexif()
            exif[274] = 6  # Rotate clockwise: red becomes the top half.
            image.save(path, exif=exif)
            original = load_original(path)
            self.assertEqual(original.size, (20, 40))
            self.assertNotEqual(original.getexif().get(274), 6)
            actual = prepare_image(path)
            self.assertEqual(actual.mode, 'RGB')
            self.assertEqual(actual.size, (320, 240))
            self.assertEqual(actual.getpixel((160, 10)), (255, 0, 0))
            self.assertEqual(actual.getpixel((160, 230)), (0, 0, 255))
            self.assertEqual(actual.tobytes(), original.resize((320, 240), Image.Resampling.BILINEAR).tobytes())

    def test_boxes_map_back_to_portrait_without_changing_board_coordinates(self):
        box = dict(track_id=25, score=.99884, x1=102, y1=101, x2=136, y2=124)
        mapped = map_boxes([box], (1080, 1440))[0]
        self.assertEqual([mapped[k] for k in ('x1', 'y1', 'x2', 'y2')],
                         [344.25, 606, 459, 744])
        self.assertEqual((mapped['score'], mapped['track_id']), (.99884, 25))
        self.assertEqual((box['x1'], box['y1']), (102, 101))
        full = dict(box, x1=-1, y1=0, x2=321, y2=240)
        edge = map_boxes([full], (1920, 1080))[0]
        self.assertEqual([edge[k] for k in ('x1', 'y1', 'x2', 'y2')], [0, 0, 1920, 1080])
        self.assertEqual(map_boxes([], (1080, 1440)), [])

    def test_original_evidence_preserves_source_resolution_and_separate_coordinates(self):
        original = Image.new('RGB', (1080, 1440), 'black')
        original.paste('blue', (0, 0, 1080, 500))
        image = original.resize((320, 240), Image.Resampling.BILINEAR)
        box = dict(track_id=25, score=.99884, x1=102, y1=101, x2=136, y2=124)
        result = dict(frame_id=7, error=0, input_sha256=hashlib.sha256(image.tobytes()).hexdigest(),
                      event=0, boxes=[box])
        with tempfile.TemporaryDirectory() as directory:
            output = Path(save_detection(directory, image, result, original_image=original))
            record = json.loads((output/'result.json').read_text())
            self.assertEqual(record['boxes'], [box])
            self.assertEqual(record['original_boxes'][0]['x1'], 344.25)
            self.assertEqual(record['original_size'], [1080, 1440])
            self.assertEqual(record['image_transform']['source_size'], [1080, 1440])
            self.assertEqual(record['image_transform']['input_size'], [320, 240])
            self.assertEqual(record['original_rgb_sha256'], hashlib.sha256(original.tobytes()).hexdigest())
            for name, expected in [('input.png', image), ('original.png', original)]:
                with Image.open(output/name) as saved:
                    self.assertEqual(saved.size, expected.size)
                    self.assertEqual(saved.tobytes(), expected.tobytes())
            with Image.open(output/'original_annotated.png') as saved:
                self.assertEqual(saved.size, (1080, 1440))
                self.assertEqual(saved.getpixel((344, 606)), (0, 255, 136))
            self.assertEqual(original.getpixel((344, 606)), (0, 0, 0))
            self.assertNotIn('original_boxes', result)

    def test_wrong_original_is_rejected_before_creating_evidence(self):
        image = Image.new('RGB', (320, 240), 'black')
        result = dict(frame_id=7, error=0, input_sha256=hashlib.sha256(image.tobytes()).hexdigest(), boxes=[])
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(ValueError):
                save_detection(directory, image, result,
                               original_image=Image.new('RGB', (1080, 1440), 'white'))
            self.assertEqual(list(Path(directory).iterdir()), [])

    def test_evidence_keeps_exact_input_and_rejects_wrong_image(self):
        image = Image.new('RGB', (320, 240), 'black')
        digest = hashlib.sha256(image.tobytes()).hexdigest()
        result = dict(frame_id=5, error=0, input_sha256=digest, event=1,
                      boxes=[dict(track_id=1, score=.9, x1=20, y1=20, x2=50, y2=50)])
        with tempfile.TemporaryDirectory() as directory:
            output = Path(save_detection(directory, image, result, 'fixture', '127.0.0.1'))
            self.assertEqual(json.loads((output/'result.json').read_text())['input_sha256'], digest)
            with Image.open(output/'input.png') as saved:
                self.assertEqual(saved.tobytes(), image.tobytes())
            self.assertEqual(image.getpixel((20, 20)), (0, 0, 0))
            with Image.open(output/'annotated.png') as saved:
                self.assertNotEqual(saved.getpixel((20, 20)), (0, 0, 0))
            with self.assertRaises(ValueError):
                save_detection(directory, Image.new('RGB', (320, 240), 'white'), result)

    def test_commit_ack_loss_recovers_matching_result_without_reupload(self):
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as reservation:
            reservation.bind(('127.0.0.1', 0))
            port = reservation.getsockname()[1]
        ops = []
        def handle(sock, data, peer, _):
            fields = upload.HEADER.unpack_from(data)
            ops.append(fields[2])
            if fields[2] == 3:
                sock.sendto(result_packet(fields[4], stamp=fields[-1]), ('127.0.0.1', port))
            else:
                sock.sendto(ngu_ack(data), peer)
        def fast_uploader(*args, **kwargs):
            return upload.Uploader(*args, timeout=.01, retries=2, **kwargs)
        with Server(handle) as server, patch('nigo_host.client.Uploader', side_effect=fast_uploader):
            result = Host(Endpoint('127.0.0.1', '127.0.0.1'), server.port(),
                          result_port=port, result_source_port=server.port()).detect(bytes(230400), result_timeout=.2)
        self.assertFalse(result['commit_ack'])
        self.assertEqual(ops.count(1), 1)
        self.assertEqual(ops.count(3), 2)

    def test_data_timeout_is_not_treated_as_commit(self):
        with Server(lambda *args: None) as server:
            with patch('nigo_host.client.Uploader') as uploader:
                uploader.return_value.upload.side_effect = upload.UploadTimeout(2)
                with self.assertRaises(upload.UploadTimeout) as caught:
                    Host(Endpoint('127.0.0.1', '127.0.0.1'), server.port(), result_port=0).detect(bytes(230400))
                self.assertEqual(caught.exception.op, 2)

    def test_foreign_result_port_cannot_supply_detection(self):
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as reservation:
            reservation.bind(('127.0.0.1', 0))
            port = reservation.getsockname()[1]
        def handle(sock, data, peer, _):
            fields = upload.HEADER.unpack_from(data)
            if fields[2] == 3:
                sock.sendto(result_packet(fields[4], stamp=fields[-1]), ('127.0.0.1', port))
            sock.sendto(ngu_ack(data), peer)
        with Server(handle) as server:
            with self.assertRaises(TimeoutError):
                Host(Endpoint('127.0.0.1', '127.0.0.1'), server.port(), result_port=port,
                     result_source_port=0).detect(bytes(230400), result_timeout=.03)


if __name__ == '__main__':
    unittest.main()
