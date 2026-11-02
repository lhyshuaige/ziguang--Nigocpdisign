"""Read-only AI progress and retained-result RPC for the diagnostic app."""
import secrets
import socket
import struct
import time

from .protocol import decode_result

HEADER = struct.Struct('!4s4I')
STATUS = struct.Struct('!23I')
FIELDS = ['model_valid', 'runtime_state', 'layer', 'job', 'submitted', 'completion_start',
          'ai_status', 'completions', 'last_error', 'frame_ready', 'result_pending',
          'frame_id', 'timestamp', 'elapsed_ms', 'result_sequence', 'upload_active',
          'upload_offset', 'reads_low', 'compute_low', 'busy_low', 'wait_low', 'model_crc', 'build_id']
STATES = ['idle', 'packing', 'cache sync', 'submitting', 'waiting for hardware', 'collecting', 'draining error']


class FaceRPCError(RuntimeError):
    def __init__(self, code):
        self.code = code
        super().__init__('AI RPC error %d' % code)


class FaceClient:
    def __init__(self, endpoint, port=5001, timeout=.25, retries=3):
        self.peer = (endpoint.board, port)
        self.socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            self.socket.bind((endpoint.local, 0))
        except Exception:
            self.socket.close()
            raise
        self.timeout, self.retries = timeout, retries

    def close(self):
        self.socket.close()

    def call(self, op=1, frame_id=0):
        sequence = secrets.randbits(32)
        request = HEADER.pack(b'NFC1', 1, op, sequence, frame_id)
        for _ in range(self.retries):
            self.socket.sendto(request, self.peer)
            deadline = time.monotonic()+self.timeout
            while time.monotonic() < deadline:
                self.socket.settimeout(max(.001, deadline-time.monotonic()))
                try:
                    data, source = self.socket.recvfrom(2048)
                except socket.timeout:
                    break
                if source != self.peer or len(data) < HEADER.size:
                    continue
                magic, version, operation, seq, error = HEADER.unpack_from(data)
                if (magic, version, operation, seq) != (b'NFS1', 1, op, sequence):
                    continue
                if error:
                    if len(data) != HEADER.size:
                        raise ValueError('malformed AI RPC error')
                    raise FaceRPCError(error)
                body = data[HEADER.size:]
                if op == 1:
                    if len(body) != STATUS.size:
                        raise ValueError('AI status length mismatch')
                    status = dict(zip(FIELDS, STATUS.unpack(body)))
                    if status['runtime_state'] >= len(STATES) or status['layer'] > 42:
                        raise ValueError('AI status state/layer mismatch')
                    status['state_name'] = STATES[status['runtime_state']]
                    return status
                result = decode_result(body)
                if result['frame_id'] != frame_id:
                    raise ValueError('retained result frame mismatch')
                return result
        raise TimeoutError('AI 状态查询超时；原版固件不支持 NFC1，需加载带状态查询的 AI 程序')
