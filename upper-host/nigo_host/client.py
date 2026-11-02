"""Blocking operations for GUI workers and headless board checks."""
import ipaddress
import hashlib
import secrets
import socket
import time
from contextlib import closing
from dataclasses import dataclass

from .program import ProgramClient, validate_image
from .upload import Uploader, UploadTimeout
from .face import validate_model
from .face_rpc import FaceClient, FaceRPCError
from .protocol import decode_result
from . import rx


@dataclass(frozen=True)
class Endpoint:
    board: str = '192.168.1.50'
    local: str = '192.168.1.100'

    def __post_init__(self):
        for value in (self.board, self.local):
            address = ipaddress.IPv4Address(value)
            if address.is_unspecified or address.is_multicast or int(address) == 0xffffffff:
                raise ValueError('请填写板卡和有线网卡的具体 IPv4 地址')
        if self.board == self.local:
            # Loopback is useful for isolated protocol tests.
            if not ipaddress.IPv4Address(self.board).is_loopback:
                raise ValueError('板卡 IP 和 PC IP 不能相同')


class Host:
    def __init__(self, endpoint, control_port=5001, data_port=5000, result_port=5002,
                 result_source_port=5002):
        self.endpoint = endpoint
        self.control_port = control_port
        self.data_port = data_port
        self.result_port = result_port
        self.result_source_port = result_source_port

    def boot_query(self):
        with closing(ProgramClient(self.endpoint.board, self.control_port,
                                   bind=self.endpoint.local)) as client:
            return client.control(1)

    def program(self, blob, progress=None):
        entry, crc = validate_image(blob)  # Validate before sending anything.
        with closing(ProgramClient(self.endpoint.board, self.control_port,
                                   bind=self.endpoint.local)) as client:
            client.control(1)  # Fail without overwriting if the ROM isn't listening.
            client.download(blob, progress)
        return dict(entry=entry, crc=crc, execute_ack=True)

    def _control(self, sock):
        sock.bind((self.endpoint.local, 0))
        return rx.Control(sock, self.endpoint.board, control_port=self.control_port,
                          data_port=self.data_port)

    def receiver_query(self):
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            return self._control(sock).call(2)

    def send_frame(self, body, width, height, rgb565, progress=None):
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            control = self._control(sock)
            before = control.call(2)
            frame = rx.upload(control, body, width, height, rgb565,
                              retries=0, progress=progress)
            after = control.call(2)
            if after['status'] & 0x33:
                raise RuntimeError('帧已提交，但缓冲区未确认释放：' + str(after))
            if any(after[k] != before[k] for k in ('frames_bad', 'packets_bad')):
                raise RuntimeError('接收错误计数增加：' + str(after))
            if ((after['frames_ok']-before['frames_ok']) & 0xffffffff) != 1:
                raise RuntimeError('完整帧计数增量不等于 1：' + str(after))
            return dict(frame=frame, receiver=after, ddr_pixels_verified=False)

    def model(self, blob, progress=None):
        metadata = validate_model(blob)  # Reject before opening a network socket.
        started = time.monotonic()
        with closing(Uploader(self.endpoint.board, self.control_port,
                              bind=self.endpoint.local)) as client:
            client.upload(blob, 1, secrets.randbits(32) or 1, progress=progress)
        return dict(metadata, committed=True, upload_seconds=time.monotonic()-started)

    def face_status(self):
        with closing(FaceClient(self.endpoint, self.control_port)) as client:
            return client.call()

    def detect(self, pixels, progress=None, result_timeout=60, status_callback=None):
        if len(pixels) != 320*240*3:
            raise ValueError('frame must be 320x240 RGB888')
        if result_timeout <= 0:
            raise ValueError('result timeout must be positive')
        frame_id = secrets.randbits(32) or 1
        stamp = int(time.time()*1000) & 0xffffffff
        snapshots = []
        def finish(result, transport):
            if result['frame_id'] != frame_id or result['timestamp'] != stamp:
                return None
            result.update(roundtrip_seconds=time.monotonic()-started, upload_seconds=uploaded-started,
                          commit_ack=commit_ack, input_sha256=hashlib.sha256(pixels).hexdigest(),
                          result_transport=transport, status_snapshots=snapshots)
            if result['error']:
                raise RuntimeError('板端 AI 返回错误码：%d' % result['error'])
            return result
        # Listen before COMMIT; a fast result may arrive before its upload ACK.
        # No SO_REUSEADDR: two viewers must not silently steal each other's results.
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as listener:
            listener.bind((self.endpoint.local, self.result_port))
            started = time.monotonic()
            commit_ack = True
            with closing(Uploader(self.endpoint.board, self.control_port,
                                  bind=self.endpoint.local)) as client:
                try:
                    client.upload(pixels, 2, frame_id, timestamp=stamp, progress=progress)
                except UploadTimeout as error:
                    if error.op != 3:
                        raise
                    # A matching board result proves COMMIT was processed, even
                    # if all COMMIT acknowledgements were lost. Never resend the frame.
                    commit_ack = False
            uploaded = time.monotonic()
            deadline = time.monotonic() + result_timeout
            next_status = uploaded + 1
            with closing(FaceClient(self.endpoint, self.control_port, timeout=.2, retries=1)) as rpc:
                while time.monotonic() < deadline:
                    if time.monotonic() >= next_status:
                        next_status = time.monotonic() + 2
                        try:
                            state = rpc.call()
                            snapshots.append(state)
                            snapshots[:] = snapshots[-60:]
                            if status_callback:
                                status_callback(state)
                            if state['frame_id'] == frame_id and state['timestamp'] == stamp and not state['runtime_state']:
                                recovered = finish(rpc.call(2, frame_id), 'retained RPC')
                                if recovered:
                                    return recovered
                        except TimeoutError:
                            # Original AI application has no RPC. Keep listening
                            # for NGE1 without repeatedly sending unsupported commands.
                            if not snapshots:
                                next_status = deadline
                        except FaceRPCError as error:
                            if error.code not in (2, 4):
                                raise
                    listener.settimeout(max(.001, min(deadline, next_status)-time.monotonic()))
                    try:
                        data, source = listener.recvfrom(2048)
                    except socket.timeout:
                        continue
                    if source != (self.endpoint.board, self.result_source_port):
                        continue
                    try:
                        result = decode_result(data)
                    except ValueError:
                        continue
                    matched = finish(result, 'UDP 5002')
                    if matched:
                        return matched
        prefix = '图像上传已确认' if commit_ack else '图像 COMMIT 确认丢失且未收到检测结果，提交状态未知'
        if snapshots:
            last = snapshots[-1]
            prefix += '；板端 %s，层 %d/42，完成任务 %d，硬件状态 0x%x' % (
                last['state_name'], last['layer'], last['completions'], last['ai_status'])
        raise TimeoutError(prefix + '；等待板端结果超时，请检查 AI 应用、模型和 UDP 5002')
