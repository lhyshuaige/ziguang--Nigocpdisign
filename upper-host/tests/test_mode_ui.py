"""Tk lifecycle regression using injected mode service; no board traffic."""
import threading,time,tkinter as tk,unittest
from unittest.mock import patch
import app as gui

class Stream:
    latest=None;status=None;error=None
    def __init__(self,*a,**k):self.stopped=False
    def start(self):pass
    def stop(self):self.stopped=True
    def stats(self):return dict(received=0,dropped=0,invalid=0,fps=0,age=None)

class ModeUITests(unittest.TestCase):
    def setUp(self):
        self.requests=[];self.errors=[]
        def activate(endpoint,mode,progress=None,**kw):
            self.requests.append(mode)
            return dict(active=mode,target=mode,generation=len(self.requests),build_id=123,flags=1 if mode==2 else 0)
        self.modepatch=patch('app.activate_cpu_mode',side_effect=activate);self.modepatch.start()
        self.streampatch=patch('app.ArcadeStream',Stream);self.streampatch.start()
        self.root=tk.Tk();self.root.withdraw();self.app=gui.App(self.root)
        self.root.report_callback_exception=lambda *args:self.errors.append(args)
        self.root.update()
    def tearDown(self):
        self.app.close();self.streampatch.stop();self.modepatch.stop()
        self.assertFalse(self.errors)
    def until(self,condition):
        end=time.monotonic()+3
        while not condition() and time.monotonic()<end:self.root.update();time.sleep(.01)
        self.assertTrue(condition())
    def tab(self,mode):
        tab=next(tab for tab,n in self.app.page_modes.items() if n==mode)
        self.app.tabs.select(tab);self.root.update()
    def test_tab_switch_auto_starts_game_and_releases_stream(self):
        self.tab(4);self.until(lambda:self.app.game_stream is not None)
        stream=self.app.game_stream;self.assertEqual(self.requests,[4])
        self.tab(2);self.until(lambda:self.app.mode_state['active']==2 and not self.app.busy)
        self.assertTrue(stream.stopped);self.assertIsNone(self.app.game_stream)
        self.assertIn('保留',self.app.ai_status.get());self.assertEqual(self.requests,[4,2])
    def test_busy_operation_finishes_then_last_tab_wins(self):
        gate=threading.Event();self.app.submit('模拟任务',lambda h,p:gate.wait(2))
        self.tab(4);self.tab(1);self.root.update();self.assertEqual(self.requests,[])
        gate.set();self.until(lambda:self.app.mode_state is not None and not self.app.busy)
        self.assertEqual(self.requests,[1]);self.assertIsNone(self.app.game_stream)
    def test_leaving_to_connection_page_cancels_queued_switch(self):
        self.tab(4);self.app.tabs.select(self.app.tabs.tabs()[0]);self.root.update()
        self.assertIsNone(self.app.pending_mode);self.assertEqual(self.requests,[])
    def test_operation_consumes_same_pending_mode(self):
        self.tab(1);self.app.submit('收图查询',lambda h,p:{},mode=1)
        self.until(lambda:not self.app.busy)
        self.assertEqual(self.requests,[1]);self.assertIsNone(self.app.pending_mode)
