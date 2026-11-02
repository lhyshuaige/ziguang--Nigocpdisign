"""Nigo LG100 desktop host. All inference runs on the board."""
import json
from contextlib import closing
import queue
import struct
import threading
import time
from pathlib import Path
import tkinter as tk
from tkinter import filedialog, messagebox, ttk
from tkinter.scrolledtext import ScrolledText

from PIL import Image, ImageTk
from nigo_host.client import Endpoint, Host
from nigo_host.upload import BusyError
from nigo_host.coremark import CoreMarkClient
from nigo_host.arcade import ArcadeStream, PALETTE as GAME_PALETTE, NAMES as GAME_NAMES
from nigo_host.modes import activate as activate_cpu_mode, NAMES as MODE_NAMES
from nigo_host.face import FRAME_SIZE, load_original, map_boxes, save_detection

ROOT = Path(__file__).resolve().parent
FIRMWARE = {
    '统一多模式固件（推荐）': ROOT / 'assets/firmware/runtime.ngb',
    '图像接收验证': ROOT / 'assets/firmware/receiver.ngb',
    '四按键 / LED 验证': ROOT / 'assets/firmware/keys_led.ngb',
    'UltraFace 人脸检测': ROOT / 'assets/firmware/ultraface.ngb',
    'CoreMark 1.0 CPU 测试': ROOT / 'assets/firmware/coremark.ngb',
    '多游戏合集': ROOT / 'assets/firmware/arcade.ngb',
}


class App:
    def __init__(self, root):
        self.root = root
        root.title('Nigo LG100 · 上位机')
        root.geometry('1080x820')
        root.minsize(950, 760)
        self.events = queue.Queue()
        self.busy = False
        self.widgets = []
        self.repeat = False
        self.repeat_timer = None
        self.photo = None
        self.latest_result = None
        self.image = Image.new('RGB', (320, 240))
        self.image.putdata([((x*255)//319, (y*255)//239, (x+y)%256)
                            for y in range(240) for x in range(320)])
        self.original_image = self.image.copy()
        self.preview_mode = tk.StringVar(value='原图')
        self.image_label = '内置渐变图（用于传输验证）'
        self.board = tk.StringVar(value='192.168.1.50')
        self.local = tk.StringVar(value='192.168.1.100')
        self.status = tk.StringVar(value='就绪 · 尚未查询板卡')
        self.firmware = tk.StringVar(value=next(iter(FIRMWARE)))
        self.program_path = tk.StringVar(value=str(FIRMWARE[self.firmware.get()]))
        self.model_path = tk.StringVar(value=str(ROOT / 'assets/model/ultraface.ngm'))
        self.format = tk.StringVar(value='RGB565')
        self.interval = tk.StringVar(value='5')
        self.rx_status = tk.StringVar(value='等待查询图像接收应用')
        self.ai_status = tk.StringVar(value='进入本页自动切换 AI；首次上传模型后，正常切换模式会保留模型。')
        self.model_status = tk.StringVar(value='配套冻结模型 · 上传前检查文件完整性和固件兼容性')
        self.cm_status = tk.StringVar(value='进入本页自动切换 CoreMark；计时结束后才处理模式切换。')
        self.game_status = tk.StringVar(value='进入本页自动切换游戏并接收菜单；使用板上 KEY1～KEY4 操作。')
        self.mode_state = None
        self.pending_mode = None
        self.mode_timer = None
        self.cpu_mode_status = tk.StringVar(value='板端模式尚未查询 · 首次从旧程序迁移需按一次 KEY0')
        self.game_stream = None
        self.game_image = None
        self.game_frame_id = None
        self.game_error_reported = False
        self.source = tk.StringVar(value=self.image_label)
        self._build()
        self._draw()
        ROOT.joinpath('logs').mkdir(exist_ok=True)
        self.log_path = ROOT / 'logs' / time.strftime('session_%Y%m%d_%H%M%S.jsonl')
        self.log('启动', {'note': '未自动连接或切换板端应用'})
        self.poll_timer = root.after(80, self._poll)
        self.game_timer = root.after(16, self._game_poll)
        root.protocol('WM_DELETE_WINDOW', self.close)

    def _button(self, parent, title, command):
        widget = ttk.Button(parent, text=title, command=command)
        self.widgets.append((widget, 'normal'))
        return widget

    def _entry(self, parent, variable, width=20):
        widget = ttk.Entry(parent, textvariable=variable, width=width)
        self.widgets.append((widget, 'normal'))
        return widget

    def _combo(self, parent, variable, values, width):
        widget = ttk.Combobox(parent, textvariable=variable, values=values,
                              state='readonly', width=width)
        self.widgets.append((widget, 'readonly'))
        return widget

    def _build(self):
        style = ttk.Style()
        style.theme_use('clam')
        style.configure('.', font=('Microsoft YaHei UI', 10), background='#f4f7fa', foreground='#182b3c')
        style.configure('TButton', padding=(12, 7))
        style.configure('TNotebook.Tab', padding=(20, 9))
        style.configure('Title.TLabel', font=('Microsoft YaHei UI', 22, 'bold'))
        style.configure('Hint.TLabel', foreground='#526474')
        page = ttk.Frame(self.root, padding=18)
        page.pack(fill='both', expand=True)
        title = ttk.Frame(page)
        title.pack(fill='x')
        ttk.Label(title, text='NIGO / LG100', style='Title.TLabel').pack(side='left')
        ttk.Label(title, text='网口调试 · 人脸检测 · Nigo CPU 游戏', style='Hint.TLabel').pack(side='left', padx=20)
        network = ttk.Frame(page, padding=(0, 12))
        network.pack(fill='x')
        for label, value in [('板卡 IP', self.board), ('PC 有线 IP', self.local)]:
            ttk.Label(network, text=label).pack(side='left', padx=(0, 8))
            self._entry(network, value, 17).pack(side='left', padx=(0, 24))
        ttk.Label(network, text='千兆直连 · UDP', style='Hint.TLabel').pack(side='right')
        ttk.Label(page, textvariable=self.cpu_mode_status, style='Hint.TLabel').pack(anchor='w', pady=(0, 7))
        tabs = ttk.Notebook(page)
        self.tabs = tabs
        tabs.pack(fill='x')
        boot = ttk.Frame(tabs, padding=14)
        receive = ttk.Frame(tabs, padding=14)
        ai = ttk.Frame(tabs, padding=14)
        benchmark = ttk.Frame(tabs, padding=14)
        self.game_tab = ttk.Frame(tabs, padding=14)
        tabs.add(boot, text='01  程序与连接')
        tabs.add(receive, text='02  图像接收')
        tabs.add(ai, text='03  人脸检测')
        tabs.add(benchmark, text='04  CoreMark')
        tabs.add(self.game_tab, text='05  游戏')
        self.page_modes = {str(receive):1, str(ai):2, str(benchmark):3, str(self.game_tab):4}
        tabs.bind('<<NotebookTabChanged>>', self._tab_changed)
        ttk.Label(boot, text='首次启用：按一次 KEY0 后点击功能页，自动安装统一固件。以后切换页面即可切换 CPU 模式。',
                  style='Hint.TLabel').pack(anchor='w')
        self._button(boot, '连接 / 安装统一固件', lambda: self.request_mode(0)).pack(anchor='w', pady=(6,0))
        row = ttk.Frame(boot)
        row.pack(fill='x', pady=8)
        combo = self._combo(row, self.firmware, list(FIRMWARE), 34)
        combo.pack(side='left', padx=(0, 10))
        combo.bind('<<ComboboxSelected>>', lambda _: self.program_path.set(str(FIRMWARE[self.firmware.get()])))
        self._button(row, '选择 .ngb…', self.choose_program).pack(side='left', padx=4)
        self._button(row, '查询 Bootloader', self.query_boot).pack(side='left', padx=4)
        self._button(row, '下载所选固件', self.download).pack(side='left', padx=4)
        ttk.Label(boot, textvariable=self.program_path, style='Hint.TLabel', wraplength=950).pack(anchor='w')

        ttk.Label(receive, text='进入本页自动切换收图模式。发送完成后检查完整帧与错误计数。',
                  style='Hint.TLabel').pack(anchor='w')
        row = ttk.Frame(receive)
        row.pack(fill='x', pady=8)
        self._combo(row, self.format, ['RGB565', 'Gray8'], 10).pack(side='left', padx=(0, 10))
        self._button(row, '查询接收状态', self.query_rx).pack(side='left', padx=4)
        self._button(row, '发送当前图片', self.send_rx).pack(side='left', padx=4)
        ttk.Label(row, text='320 × 240 · 单帧发送', style='Hint.TLabel').pack(side='left', padx=14)
        ttk.Label(receive, textvariable=self.rx_status, wraplength=950).pack(anchor='w')

        row = ttk.Frame(ai)
        row.pack(fill='x')
        self._entry(row, self.model_path, 61).pack(side='left', fill='x', expand=True)
        self._button(row, '选择模型…', self.choose_model).pack(side='left', padx=5)
        self._button(row, '上传模型', self.send_model).pack(side='left')
        ttk.Label(ai, textvariable=self.model_status, style='Hint.TLabel', wraplength=950).pack(anchor='w')
        row = ttk.Frame(ai)
        row.pack(fill='x', pady=8)
        self._button(row, '检测当前图片', self.detect).pack(side='left')
        self._button(row, '查询 AI 状态', self.query_ai).pack(side='left', padx=5)
        ttk.Label(row, text='间隔（秒）').pack(side='left', padx=(16, 6))
        self._combo(row, self.interval, ['2', '5', '10', '30', '60'], 4).pack(side='left')
        self._button(row, '开始重复检测', self.start_repeat).pack(side='left', padx=6)
        # Stopping repeat is available while the current single frame finishes.
        ttk.Button(row, text='停止重复', command=self.stop_repeat).pack(side='left')
        ttk.Label(ai, textvariable=self.ai_status, wraplength=950).pack(anchor='w')
        ttk.Label(ai, text='成功结果自动保存到 logs/faces：原图及标框、AI 输入及标框、JSON。检测位置，不识别身份。',
                  style='Hint.TLabel', wraplength=950).pack(anchor='w')

        ttk.Label(benchmark, text='CoreMark 1.0 · 100 MHz CPU · DDR 执行 · 两组种子校验',
                  style='Hint.TLabel').pack(anchor='w')
        row = ttk.Frame(benchmark)
        row.pack(fill='x', pady=8)
        self._button(row, '运行并回传（自动迭代）', self.run_coremark).pack(side='left')
        self._button(row, '取回最近成绩', self.latest_coremark).pack(side='left', padx=8)
        ttk.Label(row, text='运行期间请勿复位；计时结束后回传', style='Hint.TLabel').pack(side='left', padx=8)
        ttk.Label(benchmark, textvariable=self.cm_status, wraplength=950).pack(anchor='w')

        ttk.Label(self.game_tab, text='四款游戏：飞机大战 + Boss / 贪吃蛇 / 打砖块 / 落块游戏',
                  style='Hint.TLabel').pack(anchor='w')
        row = ttk.Frame(self.game_tab)
        row.pack(fill='x', pady=8)
        self._button(row, '进入游戏模式', self.download_game).pack(side='left')
        self._button(row, '重新接收画面', self.start_game).pack(side='left', padx=8)
        ttk.Button(row, text='停止接收', command=self.stop_game).pack(side='left')
        ttk.Label(row, text='菜单：KEY1 上 / KEY2 下 / KEY3 确认', style='Hint.TLabel').pack(side='left', padx=12)
        ttk.Label(self.game_tab, text='游戏中按住 KEY1 + KEY2 约 0.75 秒回菜单。KEY0 是复位，REST 不用于游戏。',
                  style='Hint.TLabel').pack(anchor='w')
        ttk.Label(self.game_tab, textvariable=self.game_status, wraplength=950).pack(anchor='w')

        footer = ttk.Frame(page)
        footer.pack(side='bottom', fill='x')
        self.progress = ttk.Progressbar(footer, maximum=100)
        self.progress.pack(fill='x', pady=(8, 6))
        ttk.Label(footer, textvariable=self.status, wraplength=950).pack(anchor='w')
        content = ttk.Frame(page, padding=(0, 12, 0, 6))
        content.pack(fill='both', expand=True)
        preview = ttk.Frame(content)
        preview.pack(side='left', fill='both', expand=True)
        row = ttk.Frame(preview)
        self.image_toolbar = row
        row.pack(fill='x', pady=(0, 8))
        self._button(row, '选择图片…', self.choose_image).pack(side='left')
        self._button(row, '使用测试图', self.test_image).pack(side='left', padx=6)
        self._button(row, '参考人脸图', self.reference_image).pack(side='left')
        ttk.Label(row, text='预览', style='Hint.TLabel').pack(side='left', padx=(8, 4))
        preview_combo = self._combo(row, self.preview_mode, ['原图', 'AI 输入'], 8)
        preview_combo.pack(side='left')
        preview_combo.bind('<<ComboboxSelected>>', lambda _: self._draw())
        self.source_caption = ttk.Label(preview, textvariable=self.source, style='Hint.TLabel', wraplength=620)
        self.source_caption.pack(side='bottom', anchor='w', pady=(5, 0))
        self.game_caption = ttk.Label(preview, text='Nigo CPU 绘制 · 320 × 240 · 网口回传画面', style='Hint.TLabel')
        self.canvas = tk.Canvas(preview, background='#101e2b', highlightthickness=0,
                                width=590, height=370)
        self.canvas.pack(fill='both', expand=True)
        self.canvas.bind('<Configure>', lambda _: self._draw())
        side = ttk.Frame(content, padding=(16, 0, 0, 0), width=320)
        side.pack(side='right', fill='y')
        ttk.Label(side, text='操作记录', font=('Microsoft YaHei UI', 12, 'bold')).pack(anchor='w', pady=(8, 10))
        self.display_hint = tk.StringVar(value='图像接收：已具备帧提交验证\nDDR 像素回读 CRC：尚未接入\nAI 结果：仅显示板端返回数据')
        ttk.Label(side, textvariable=self.display_hint,
                  style='Hint.TLabel', justify='left').pack(side='bottom', anchor='w', pady=(10, 0))
        self.history = ScrolledText(side, width=34, height=16, wrap='word', state='disabled',
                                    font=('Microsoft YaHei UI', 9), relief='flat', background='#f1f5f8')
        self.history.pack(fill='both', expand=True)

    def log(self, action, details):
        record = dict(time=time.strftime('%Y-%m-%dT%H:%M:%S%z'), action=action, details=details)
        self.history.configure(state='normal')
        self.history.insert('end', time.strftime('%H:%M:%S') + '  ' + action + '\n' +
                            json.dumps(details, ensure_ascii=False, indent=2) + '\n\n')
        self.history.see('end')
        self.history.configure(state='disabled')
        try:
            with self.log_path.open('a', encoding='utf-8') as stream:
                stream.write(json.dumps(record, ensure_ascii=False) + '\n')
        except OSError as error:
            self.status.set('日志写入失败：' + str(error))

    def submit(self, title, operation, complete=None, repeating=False, mode=None):
        if self.busy:
            return
        if mode is not None and self.pending_mode == mode:
            self.pending_mode = None
            if self.mode_timer is not None:
                self.root.after_cancel(self.mode_timer)
                self.mode_timer = None
        if self.game_stream is not None:
            self.stop_game()
        if not repeating:
            self.stop_repeat()
        try:
            host = Host(Endpoint(self.board.get().strip(), self.local.get().strip()))
        except ValueError as error:
            messagebox.showerror('地址格式', str(error))
            return
        self.busy = True
        for widget, _ in self.widgets:
            widget.configure(state='disabled')
        self.progress['value'] = 0
        self.status.set(title + '…')
        self.log(title + '开始', {'board': host.endpoint.board, 'local': host.endpoint.local})
        def work():
            previous = -1
            def progress(done, total):
                nonlocal previous
                percent = int(done*100/total)
                if percent != previous:
                    previous = percent
                    self.events.put(('progress', percent))
            try:
                if mode is not None:
                    state = activate_cpu_mode(host.endpoint, mode, progress)
                    self.events.put(('mode_status', state))
                result = operation(host, progress)
                self.events.put(('done', title, result, complete))
            except Exception as error:
                self.events.put(('error', title, error))
        threading.Thread(target=work, daemon=True).start()

    def _poll(self):
        while not self.events.empty():
            event = self.events.get_nowait()
            if event[0] == 'progress':
                self.progress['value'] = event[1]
                if event[1] == 100:
                    self.status.set('数据已发送，等待板端最终确认或检测结果…')
                continue
            if event[0] == 'ai_status':
                self.show_ai_status(event[1])
                continue
            if event[0] == 'mode_status':
                self.show_cpu_mode(event[1])
                continue
            self.busy = False
            for widget, state in self.widgets:
                widget.configure(state=state)
            if event[0] == 'error':
                self.stop_repeat()
                error = event[2]
                note = str(error)
                if isinstance(error, BusyError):
                    note = '板卡忙，本帧未进入推理；已停止重复检测。'
                elif isinstance(error, TimeoutError):
                    note += '\n请核对网线和 PC 有线 IP；任务运行期间请等待，正常模式切换无需 KEY0。'
                self.cpu_mode_status.set('操作未完成 · 未确认新的板端模式，详见操作记录')
                self.status.set(event[1] + '未完成 · 详见操作记录')
                self.log(event[1] + '未完成', {'error': note})
            else:
                self.progress['value'] = 100
                self.status.set(event[1] + '完成')
                self.log(event[1] + '完成', event[2])
                if event[3]:
                    event[3](event[2])
        if not self.busy and self.pending_mode is not None and self.mode_timer is None:
            self.mode_timer = self.root.after(1, self._dispatch_mode)
        self.poll_timer = self.root.after(80, self._poll)

    def request_mode(self, mode):
        self.stop_repeat()
        self.pending_mode = mode
        self.cpu_mode_status.set(('等待当前任务结束后切换到 ' if self.busy else '正在切换到 ') + MODE_NAMES[mode])
        if self.mode_timer is not None:
            self.root.after_cancel(self.mode_timer)
        self.mode_timer = self.root.after(250, self._dispatch_mode)

    def _dispatch_mode(self):
        self.mode_timer = None
        if self.busy or self.pending_mode is None:
            return
        mode, self.pending_mode = self.pending_mode, None
        self.submit('切换到 ' + MODE_NAMES[mode],
                    lambda host, progress: activate_cpu_mode(host.endpoint, mode, progress), self._mode_ready)

    def show_cpu_mode(self, state):
        self.mode_state = state
        self.cpu_mode_status.set('板端已确认：%s · 统一固件 %08x · 切换序号 %d' %
                                 (MODE_NAMES[state['active']], state['build_id'], state['generation']))
        if state['active'] == 2:
            self.ai_status.set('AI 模型已保留，可以直接检测。' if state['flags'] & 1 else '首次使用或复位后，请上传配套模型。')

    def _mode_ready(self, state):
        self.show_cpu_mode(state)
        if state['active'] == 4 and self._game_selected() and self.pending_mode is None:
            self._start_game_stream()

    def choose_program(self):
        path = filedialog.askopenfilename(initialdir=ROOT / 'assets/firmware', filetypes=[('CPU 程序', '*.ngb')])
        if path:
            self.program_path.set(path)

    def choose_model(self):
        path = filedialog.askopenfilename(initialdir=ROOT / 'assets/model', filetypes=[('模型', '*.ngm')])
        if path:
            self.model_path.set(path)

    def query_boot(self):
        self.submit('查询 Bootloader', lambda host, _: host.boot_query())

    def download(self):
        path = Path(self.program_path.get())
        if path.resolve() == FIRMWARE['统一多模式固件（推荐）'].resolve():
            self.request_mode(0)
            return
        self.submit('CPU 程序下载', lambda host, progress: host.program(path.read_bytes(), progress),
                    lambda _: self.status.set('程序 CRC 校验和执行请求已确认；请用对应功能验证应用启动'))

    def query_rx(self):
        self.submit('查询接收状态', lambda host, _: host.receiver_query(), self.show_rx, mode=1)

    def show_rx(self, result):
        state = result.get('receiver', result)
        self.rx_status.set('完整帧 %d  |  错误帧 %d  |  错误包 %d  |  DDR 像素 CRC 未验证' %
                           (state['frames_ok'], state['frames_bad'], state['packets_bad']))

    def send_rx(self):
        image = self.image.copy()
        rgb565 = int(self.format.get() == 'RGB565')
        pixels = image.tobytes()
        body = (b''.join(struct.pack('<H', ((r>>3)<<11)|((g>>2)<<5)|(b>>3))
                         for r,g,b in zip(pixels[0::3], pixels[1::3], pixels[2::3])) if rgb565 else image.convert('L').tobytes())
        self.submit('图像接收验证', lambda host, progress: host.send_frame(body, 320, 240, rgb565, progress), self.show_rx, mode=1)

    def send_model(self):
        path = Path(self.model_path.get())
        self.submit('模型上传', lambda host, progress: host.model(path.read_bytes(), progress),
                    self.show_model, mode=2)

    def show_model(self, result):
        self.model_status.set('%s · %d 层 / %d 个任务 · CRC %s · 上传 %.2f s' %
                              (result['name'], result['layers'], result['jobs'], result['crc32'], result['upload_seconds']))
        self.ai_status.set('模型提交已确认 · 可选择人脸照片并检测；复位后需重新上传')

    def query_ai(self):
        self.submit('AI 状态查询', lambda host, _: host.face_status(), self.show_ai_status, mode=2)

    def show_ai_status(self, state):
        self.ai_status.set('模型%s · %s · 层 %d/42 · 累计完成任务 %d · 硬件状态 0x%x · 应用 %08x' %
                           ('已加载' if state['model_valid'] else '未加载', state['state_name'],
                            state['layer'], state['completions'], state['ai_status'], state['build_id']))

    def coremark_job(self, latest):
        self.cm_status.set('等待板端完成性能与校验两组；自动迭代通常需要数十秒…')
        def operation(host, progress):
            with closing(CoreMarkClient(host.endpoint)) as client:
                result = client.latest(progress) if latest else client.run(progress=progress)
            stamp = time.strftime('%Y%m%d_%H%M%S')
            output = ROOT / 'logs' / ('coremark_' + stamp + '.json')
            output.write_text(json.dumps(result, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
            output.with_suffix('.txt').write_text(result['raw_log'], encoding='utf-8')
            result['saved_to'] = str(output)
            return result
        self.submit('CoreMark 回传', operation, self.show_coremark, mode=3)

    def run_coremark(self):
        self.coremark_job(False)

    def latest_coremark(self):
        self.coremark_job(True)

    def show_coremark(self, result):
        if result['valid']:
            self.cm_status.set('CoreMark %.3f  |  %.4f / MHz  |  两组 CRC 与 ≥10秒要求通过' %
                               (result['coremark'], result['coremark_per_mhz']))
        else:
            self.cm_status.set('结果已回传，但校验或时长不合格，不能作为有效 CoreMark 分数。')

    def _game_selected(self):
        return hasattr(self, 'tabs') and self.tabs.select() == str(self.game_tab)

    def _tab_changed(self, _event=None):
        if not hasattr(self, 'canvas'):
            return
        self.stop_repeat()
        if self._game_selected():
            self.stop_repeat()
            self.image_toolbar.pack_forget()
            self.source_caption.pack_forget()
            self.game_caption.pack(side='bottom', anchor='w', pady=(5, 0), before=self.canvas)
            self.display_hint.set('菜单和游戏逻辑：Nigo CPU\n操作：开发板 KEY1～KEY4\n画面：完整接收后显示')
        else:
            self.stop_game()
            self.game_caption.pack_forget()
            self.source_caption.pack(side='bottom', anchor='w', pady=(5, 0), before=self.canvas)
            self.image_toolbar.pack(fill='x', pady=(0, 8), before=self.canvas)
            self.display_hint.set('图像接收：已具备帧提交验证\nDDR 像素回读 CRC：尚未接入\nAI 结果：仅显示板端返回数据')
        self._draw()
        mode = self.page_modes.get(self.tabs.select())
        if mode is not None:
            self.request_mode(mode)
        else:
            self.pending_mode = None
            if self.mode_timer is not None:
                self.root.after_cancel(self.mode_timer)
                self.mode_timer = None

    def download_game(self):
        self.request_mode(4)

    def start_game(self):
        if self.busy:
            return
        self.tabs.select(self.game_tab)
        self.request_mode(4)

    def _start_game_stream(self):
        self.stop_repeat()
        self.stop_game()
        try:
            endpoint = Endpoint(self.board.get().strip(), self.local.get().strip())
        except ValueError as error:
            messagebox.showerror('地址格式', str(error))
            return
        self.game_image = None
        self.game_frame_id = None
        self.game_error_reported = False
        self.game_stream = ArcadeStream(endpoint)
        self.game_stream.start()
        self.game_status.set('正在连接板端游戏应用，等待画面…')
        self.log('游戏显示连接', {'board': endpoint.board, 'local': endpoint.local, 'port': 5003})
        self._draw()

    def stop_game(self):
        if self.game_stream is not None:
            stream = self.game_stream
            self.game_stream = None
            stream.stop()
            self.game_status.set('已停止接收画面；板端应用仍继续运行。')
            if hasattr(self, 'log_path'):
                self.log('游戏显示停止', stream.stats())

    def _game_poll(self):
        stream = self.game_stream
        if stream is not None:
            if stream.latest and stream.latest[0] != self.game_frame_id:
                identity, pixels, _received = stream.latest
                self.game_image = Image.frombytes('P', (320, 240), pixels)
                self.game_image.putpalette(GAME_PALETTE)
                self.game_frame_id = identity
                if self._game_selected():
                    self._draw()
            stats = stream.stats()
            if stream.error:
                self.game_status.set(stream.error)
                if not self.game_error_reported:
                    self.log('游戏显示未完成', {'error': stream.error})
                    self.game_error_reported = True
            else:
                state = stream.status
                mode = GAME_NAMES[state['mode']] if state else '等待应答'
                controls = {0:'KEY1 上 / KEY2 下 / KEY3 进入', 1:'KEY1 上 / KEY2 下 / KEY3 左 / KEY4 右，自动射击',
                            2:'KEY1 上 / KEY2 下 / KEY3 左 / KEY4 右', 3:'KEY1 左 / KEY2 右 / KEY3 发球',
                            4:'KEY1 左 / KEY2 右 / KEY3 旋转 / KEY4 落下'}
                stale = ' · 画面已停更' if stats['age'] is not None and stats['age'] > 2 else ''
                self.game_status.set('%s · 接收 %.1f FPS · 完整帧 %d · 丢帧 %d%s\n%s' %
                    (mode, stats['fps'], stats['received'], stats['dropped'], stale, controls[state['mode']] if state else '等待板端画面'))
        self.game_timer = self.root.after(16, self._game_poll)

    def choose_image(self):
        path = filedialog.askopenfilename(filetypes=[('图片', '*.png *.jpg *.jpeg *.bmp *.webp')])
        if not path:
            return
        try:
            self._set_image(load_original(path), str(Path(path)))
        except (OSError, ValueError) as error:
            messagebox.showerror('无法打开图片', str(error))

    def test_image(self):
        image = Image.new('RGB', FRAME_SIZE)
        image.putdata([((x*255)//319, (y*255)//239, (x+y)%256)
                       for y in range(240) for x in range(320)])
        self._set_image(image, self.image_label)

    def reference_image(self):
        self._set_image(load_original(ROOT/'assets/samples/sample0.png'),
                        '参考 sample0 · 预期 5 张人脸（预览不绘制参考框）')

    def _set_image(self, original, label):
        # Keep source and wire pixels paired; never derive a new source from a preview.
        self.stop_repeat()
        self.original_image = original
        self.image = original.resize(FRAME_SIZE, Image.Resampling.BILINEAR)
        self.latest_result = None
        self.source.set('%s\n原图 %d × %d · 检测输入 320 × 240 · 框映射回原图' %
                        (label, original.width, original.height))
        self.ai_status.set('当前图片待检测')
        self._draw()

    def detect(self, repeating=False):
        image = self.image.copy()
        original = self.original_image.copy()
        source = self.source.get()
        pixels = image.tobytes()
        self.latest_result = None
        self._draw()
        self.ai_status.set('正在发送当前图片并等待板端检测结果…')
        def operation(host, progress):
            result = host.detect(pixels, progress, status_callback=lambda state: self.events.put(('ai_status', state)))
            # Disk failure must not discard an otherwise valid board result.
            try:
                result['saved_to'] = save_detection(ROOT/'logs/faces', image, result, source, host.endpoint.board,
                                                    original_image=original)
            except (OSError, ValueError) as error:
                result['save_error'] = str(error)
            return result
        self.submit('人脸检测', operation,
                    self.show_detection, repeating=repeating, mode=2)

    def show_detection(self, result):
        self.latest_result = result
        event = {0: '无事件', 1: '人脸出现', 2: '人脸离开', 3: '出现 / 离开'}.get(result['event'])
        self.ai_status.set('%d 张人脸  |  板端 %d ms  |  总耗时 %.2f s  |  %s%s%s' %
                           (len(result['boxes']), result['duration_ms'], result['roundtrip_seconds'],
                            event, '  |  跟踪估计' if result['tracked'] else '',
                            '  |  保存失败，见记录' if result.get('save_error') else '  |  已保存'))
        self._draw()
        if self.repeat:
            self.repeat_timer = self.root.after(int(self.interval.get())*1000, self._repeat_tick)

    def start_repeat(self):
        self.stop_repeat()
        self.repeat = True
        self.detect(repeating=True)

    def _repeat_tick(self):
        self.repeat_timer = None
        if self.repeat and not self.busy:
            self.detect(repeating=True)

    def stop_repeat(self):
        self.repeat = False
        if self.repeat_timer is not None:
            self.root.after_cancel(self.repeat_timer)
            self.repeat_timer = None

    def _draw(self):
        if self._game_selected():
            self.canvas.delete('all')
            width, height = max(self.canvas.winfo_width(), 1), max(self.canvas.winfo_height(), 1)
            if self.game_image is None:
                self.canvas.create_text(width//2, height//2, text='NIGO ARCADE\n等待板端游戏菜单\n\n进入本页自动切换并接收画面',
                                        fill='#b8cbdf', justify='center', font=('Microsoft YaHei UI', 17))
            else:
                scale = min(width/320, height/240)
                w, h = max(1, int(320*scale)), max(1, int(240*scale))
                self.photo = ImageTk.PhotoImage(self.game_image.resize((w,h), Image.Resampling.NEAREST))
                self.canvas.create_image(width//2,height//2,image=self.photo)
            return
        width, height = max(self.canvas.winfo_width(), 1), max(self.canvas.winfo_height(), 1)
        image = self.original_image if self.preview_mode.get() == '原图' else self.image
        scale = min(width/image.width, height/image.height)
        w, h = max(1, int(image.width*scale)), max(1, int(image.height*scale))
        x, y = (width-w)//2, (height-h)//2
        self.photo = ImageTk.PhotoImage(image.resize((w, h), Image.Resampling.LANCZOS))
        self.canvas.delete('all')
        self.canvas.create_image(x, y, anchor='nw', image=self.photo)
        if self.latest_result:
            for box in map_boxes(self.latest_result['boxes'], (w, h)):
                left, top = x+box['x1'], y+box['y1']
                self.canvas.create_rectangle(left, top, x+box['x2'], y+box['y2'],
                                              outline='#22ff99', width=2)
                self.canvas.create_text(left+3, top+3, anchor='nw', fill='#22ff99',
                                        text='#%d  %.1f%%' % (box['track_id'], box['score']*100),
                                        font=('Microsoft YaHei UI', 11, 'bold'))

    def close(self):
        self.stop_repeat()
        self.stop_game()
        self.pending_mode = None
        if self.mode_timer is not None:
            self.root.after_cancel(self.mode_timer)
            self.mode_timer = None
        if self.busy:
            messagebox.showinfo('任务进行中', '已停止后续重复任务。请等待当前传输或检测结束后再关闭。')
            return
        self.root.after_cancel(self.poll_timer)
        self.root.after_cancel(self.game_timer)
        self.root.destroy()


if __name__ == '__main__':
    root = tk.Tk()
    App(root)
    root.mainloop()
