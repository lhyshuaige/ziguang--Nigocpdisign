"""Offline loopback tests; never connects to the FPGA."""
import hashlib
import json
import select
import socket
import struct
import threading
import unittest
import zlib
from pathlib import Path

from nigo_host import program, protocol, rx, upload
from nigo_host.client import Endpoint, Host


class Server:
    def __init__(self, handler, count=1):
        self.handler = handler
        self.sockets = [socket.socket(socket.AF_INET, socket.SOCK_DGRAM) for _ in range(count)]
        for sock in self.sockets:
            sock.bind(('127.0.0.1', 0))
        self.stop = threading.Event()
        self.errors = []
        self.thread = threading.Thread(target=self.run)

    def __enter__(self):
        self.thread.start()
        return self

    def __exit__(self, *args):
        self.stop.set()
        self.thread.join(2)
        for sock in self.sockets:
            sock.close()
        if self.errors and args[0] is None:
            raise self.errors[0]

    def run(self):
        try:
            while not self.stop.is_set():
                ready, _, _ = select.select(self.sockets, [], [], .02)
                for sock in ready:
                    data, peer = sock.recvfrom(4096)
                    self.handler(sock, data, peer, self.sockets.index(sock))
        except Exception as error:
            self.errors.append(error)

    def port(self, i=0):
        return self.sockets[i].getsockname()[1]


def ngu_ack(data, status=0, checksum=None):
    magic, version, op, kind, session, seq, total, offset, crc, stamp = upload.HEADER.unpack_from(data)
    at = offset+len(data)-32 if op == 2 else total if op == 3 else 0
    return upload.ACK.pack(b'NGK1', 1, op, status, session, seq, at,
                           crc if checksum is None else checksum)


def result_packet(fid, x2=110, stamp=123):
    return (protocol.RESULT.pack(b'NGE1', 1, 1, 1, fid, stamp, 7, 45, 320, 240, 1, 1) +
            protocol.BOX.pack(2, 16384, 10, 20, x2, 120))


class ProtocolTests(unittest.TestCase):
    def test_packaged_assets_and_cpu_headers(self):
        root = Path(__file__).resolve().parents[1]
        manifest = json.loads((root/'provenance.json').read_text(encoding='utf-8'))
        for path, meta in manifest.items():
            if meta['type'] != 'asset':
                continue
            data = (root/path).read_bytes()
            self.assertEqual(hashlib.sha256(data).hexdigest(), meta['source_sha256'])
            if path.endswith('.ngb'):
                program.validate_image(data)

    def test_program_corruption_rejected(self):
        image = program.pack_image(bytes(range(256)))
        for corrupt in (image[:-1], image[:40]+b'\xff'+image[41:], b'ELF'):
            with self.assertRaises(ValueError):
                program.validate_image(corrupt)

    def test_program_retries_same_packet_and_validates_execute(self):
        blob = program.pack_image(bytes(range(256))*2)
        entry, crc = program.validate_image(blob)
        received = []
        seen = set()
        reconstructed = bytearray()
        def handle(sock, data, peer, _):
            if data.startswith(b'NGBX'):
                _, _, op, session, seq, _ = program.CONTROL.unpack(data)
                sock.sendto(program.REPLY.pack(b'NGBR', 1, op, 0, session, seq, entry, crc), peer)
                return
            fields = upload.HEADER.unpack_from(data)
            received.append(data)
            if data not in seen:
                seen.add(data)
                if fields[2] == 2:
                    reconstructed.extend(data[32:])
                return  # Drop first ACK for every packet.
            sock.sendto(ngu_ack(data), peer)
        with Server(handle) as server:
            client = program.ProgramClient('127.0.0.1', server.port(), .03, 3, bind='127.0.0.1')
            try:
                progress = []
                self.assertEqual(client.download(blob, lambda a,b: progress.append(a)), entry)
                self.assertEqual(reconstructed, blob)
                self.assertEqual(progress[-1], len(blob))
                for a,b in zip(received[::2], received[1::2]):
                    self.assertEqual(a, b)
            finally:
                client.close()

    def test_uploader_ignores_stale_and_foreign_ack(self):
        rogue = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        def handle(sock, data, peer, _):
            ack = ngu_ack(data)
            rogue.sendto(ack, peer)
            fields = list(upload.ACK.unpack(ack))
            fields[5] += 1
            sock.sendto(upload.ACK.pack(*fields), peer)
            sock.sendto(ack, peer)
        try:
            with Server(handle) as server:
                client = upload.Uploader('127.0.0.1', server.port(), .1, 2, bind='127.0.0.1')
                try:
                    self.assertEqual(client.upload(b'abc'*300, 1, 99), 99)
                finally:
                    client.close()
        finally:
            rogue.close()

    def test_uploader_rejects_wrong_crc(self):
        with Server(lambda s,d,p,_: s.sendto(ngu_ack(d, checksum=0), p)) as server:
            client = upload.Uploader('127.0.0.1', server.port(), bind='127.0.0.1')
            try:
                with self.assertRaisesRegex(RuntimeError, 'different blob'):
                    client.upload(b'payload', 1, 1)
            finally:
                client.close()

    def test_busy_is_not_retried(self):
        received = []
        def handle(sock, data, peer, _):
            received.append(data)
            sock.sendto(ngu_ack(data, status=2), peer)
        with Server(handle) as server:
            client = upload.Uploader('127.0.0.1', server.port(), bind='127.0.0.1')
            try:
                with self.assertRaises(upload.BusyError):
                    client.upload(b'payload', 1, 1)
                self.assertEqual(len(received), 1)
            finally:
                client.close()

    def test_missing_ack_times_out(self):
        with Server(lambda *args: None) as server:
            client = upload.Uploader('127.0.0.1', server.port(), .01, 2, bind='127.0.0.1')
            try:
                with self.assertRaises(TimeoutError):
                    client.upload(b'payload', 1, 1)
            finally:
                client.close()

    def test_rx_packet_offsets_and_format(self):
        body = bytes(range(26))*7  # 13 x 7 RGB565.
        vectors = list(rx.packets(body, 13, 7, 1, 42, 100))
        self.assertEqual(b''.join(p[32:] for p in vectors), body)
        first, last = [rx.HEADER.unpack_from(p) for p in vectors]
        self.assertEqual(first[3:7], (256, 42, 0, 182))
        self.assertEqual(last[3:7], (257, 42, 100, 182))

    def test_invalid_rx_input_never_arms(self):
        class NoControl:
            def call(self, *args):
                raise AssertionError('must validate before ARM')
        for body,w,h,fmt in ((b'bad', 13, 7, 1), (bytes(640*480*2), 640, 480, 1)):
            with self.assertRaises(ValueError):
                rx.upload(NoControl(), body, w, h, fmt)

    def test_busy_rx_does_not_cancel_someone_elses_frame(self):
        calls = []
        class BusyControl:
            def call(self, op, *args):
                calls.append(op)
                raise rx.ReceiverError({'error': -1})
        with self.assertRaises(rx.ReceiverError):
            rx.upload(BusyControl(), b'x', 1, 1, 0)
        self.assertEqual(calls, [1])

    def test_receiver_full_roundtrip_and_release(self):
        state = dict(error=0, status=0, events=0, offset=0, frames_ok=0, frames_bad=0,
                     packets_ok=0, packets_bad=0, frame_id=0, base=0x94000000,
                     stride=64, size=0, format=0)
        reconstructed = bytearray()
        def handle(sock, data, peer, channel):
            if channel == 1:
                fields = rx.HEADER.unpack_from(data)
                self.assertEqual(fields[5], len(reconstructed))
                reconstructed.extend(data[32:])
                state['offset'] = len(reconstructed)
                state['packets_ok'] += 1
                if fields[3] & 1:
                    state['status'] = 16
                    state['frames_ok'] += 1
                return
            _, seq, op, fid, size, fmt, _, _ = rx.REQUEST.unpack(data)
            if op == 1:
                state.update(status=1, frame_id=fid, size=size, format=fmt)
            if op == 3:
                state['status'] = 32
            if op == 4:
                state['status'] = 0
            sock.sendto(rx.ACK.pack(b'NGS1', seq, op, *state.values()), peer)
        with Server(handle, 2) as server:
            host = Host(Endpoint('127.0.0.1', '127.0.0.1'), server.port(), server.port(1))
            result = host.send_frame(bytes(13*7*2), 13, 7, 1)
            self.assertEqual(len(reconstructed), 182)
            self.assertEqual(result['receiver']['status'], 0)
            self.assertFalse(result['ddr_pixels_verified'])

    def test_detection_result_before_commit_ack_is_received(self):
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as reserved:
            reserved.bind(('127.0.0.1', 0))
            port = reserved.getsockname()[1]
        def handle(sock, data, peer, _):
            fields = upload.HEADER.unpack_from(data)
            if fields[2] == 3:
                sock.sendto(b'invalid', ('127.0.0.1', port))
                sock.sendto(result_packet(fields[4] ^ 1, stamp=fields[-1]), ('127.0.0.1', port))
                sock.sendto(result_packet(fields[4], stamp=fields[-1] ^ 1), ('127.0.0.1', port))
                sock.sendto(result_packet(fields[4], stamp=fields[-1]), ('127.0.0.1', port))
            sock.sendto(ngu_ack(data), peer)
        with Server(handle) as server:
            host = Host(Endpoint('127.0.0.1', '127.0.0.1'), server.port(), result_port=port,
                        result_source_port=server.port())
            result = host.detect(bytes(320*240*3), result_timeout=.5)
            self.assertEqual(result['boxes'][0]['track_id'], 2)
            self.assertEqual(result['event'], 1)

    def test_result_port_conflict_fails_before_upload(self):
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as occupied:
            occupied.bind(('127.0.0.1', 0))
            host = Host(Endpoint('127.0.0.1', '127.0.0.1'), result_port=occupied.getsockname()[1])
            with self.assertRaises(OSError):
                host.detect(bytes(320*240*3))

    def test_bad_result_boxes_and_lengths_rejected(self):
        for data in (result_packet(1, x2=321), result_packet(1)[:-1], result_packet(1)+b'x'):
            with self.assertRaises(ValueError):
                protocol.decode_result(data)

    def test_endpoint_rejects_ambiguous_binding(self):
        for local in ('0.0.0.0', 'invalid', '192.168.1.50'):
            with self.assertRaises(ValueError):
                Endpoint(local=local)


if __name__ == '__main__':
    unittest.main()
