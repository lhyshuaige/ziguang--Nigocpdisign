"""Desktop upload/detection viewer. Run python app.py; requires Pillow.

This PC app uploads RGB data and displays board results. It runs no face model.
"""
import json,queue,socket,threading,time
from pathlib import Path
import tkinter as tk
from tkinter import filedialog,messagebox
from PIL import Image,ImageTk
from upload import Uploader,BusyError
from protocol import decode_result
HERE=Path(__file__).resolve().parent
def main():
 root=tk.Tk();root.title('Nigo LG100 · UltraFace 网口验证');events=queue.Queue(maxsize=64)
 stop=threading.Event();pending={};busy=False;waiting_until=0.;active_frame=None;identity=int(time.time())&0xffffffff;photo=None
 controls=tk.Frame(root);controls.pack(fill='x',padx=10,pady=10)
 tk.Label(controls,text='板卡 IP').pack(side='left');ip=tk.StringVar(value='192.168.1.50')
 tk.Entry(controls,textvariable=ip,width=18).pack(side='left',padx=8)
 canvas=tk.Canvas(root,width=640,height=480,bg='#171d29');canvas.pack(padx=10)
 status=tk.StringVar(value='先上传模型，再选择图片。图像 320×240；接收结果 UDP 5002。')
 tk.Label(root,textvariable=status,anchor='w').pack(fill='x',padx=10,pady=8)
 history=tk.Text(root,height=7,width=85);history.pack(padx=10,pady=8)
 def publish(item):
  try:events.put_nowait(item)
  except queue.Full:pass
 def receive():
  s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
  try:
   s.bind(('0.0.0.0',5002));s.settimeout(.2)
   while not stop.is_set():
    try:data,peer=s.recvfrom(2048)
    except socket.timeout:continue
    try:publish(('result',peer[0],decode_result(data)))
    except ValueError:continue
  except OSError as e:publish(('error',f'结果端口启动失败：{e}'))
  finally:s.close()
 threading.Thread(target=receive,daemon=True).start()
 def show(image,boxes=()):
  nonlocal photo
  photo=ImageTk.PhotoImage(image.resize((640,480),Image.Resampling.NEAREST));canvas.delete('all');canvas.create_image(0,0,image=photo,anchor='nw')
  for b in boxes:
   canvas.create_rectangle(b['x1']*2,b['y1']*2,b['x2']*2,b['y2']*2,outline='#55ed93',width=2)
   canvas.create_text(b['x1']*2,b['y1']*2,anchor='sw',text=f"{b['track_id']}  {b['score']:.2f}",fill='#55ed93')
 def worker(board,blob,kind,fid,image):
  client=None;waiting_for_result=False
  try:
   client=Uploader(board)
   if kind==2:publish(('peer',fid,client.peer[0]))
   start=time.monotonic();client.upload(blob,kind,fid);waiting_for_result=kind==2
   publish(('sent',fid,kind,time.monotonic()-start,client.peer[0]))
  except BusyError:publish(('error','板端忙，本帧跳过；不会排队积压。'))
  except Exception as e:publish(('error',str(e)))
  finally:
   if client:client.close()
   if not waiting_for_result:publish(('idle',fid))
 def model():
  nonlocal busy
  if busy:return
  path=filedialog.askopenfilename(initialdir=str(HERE.parent/'assets'),filetypes=[('Nigo model','*.ngm')])
  if not path:return
  busy=True;status.set('正在上传并校验模型……')
  threading.Thread(target=worker,args=(ip.get(),Path(path).read_bytes(),1,0x4d4f444c,None),daemon=True).start()
 def image():
  nonlocal busy,identity,active_frame
  if busy:return
  path=filedialog.askopenfilename(filetypes=[('图像','*.png *.jpg *.jpeg *.bmp')])
  if not path:return
  try:rgb=Image.open(path).convert('RGB').resize((320,240),Image.Resampling.BILINEAR)
  except Exception as e:messagebox.showerror('图片读取失败',str(e));return
  identity=(identity+1)&0xffffffff;pending[identity]=(ip.get(),rgb)
  active_frame=identity
  while len(pending)>8:pending.pop(next(iter(pending)))
  show(rgb);busy=True;status.set(f'上传帧 {identity}……')
  threading.Thread(target=worker,args=(ip.get(),rgb.tobytes(),2,identity,rgb),daemon=True).start()
 tk.Button(controls,text='上传模型',command=model).pack(side='left',padx=5)
 tk.Button(controls,text='选择图片并检测',command=image).pack(side='left',padx=5)
 log_dir=HERE.parent/'logs';log_dir.mkdir(exist_ok=True);log=(log_dir/'face_events.jsonl').open('a',encoding='utf-8')
 last_sequence={}
 def update():
  nonlocal busy,waiting_until,active_frame
  for _ in range(64):
   try:e=events.get_nowait()
   except queue.Empty:break
   if e[0]=='idle':
    if active_frame is None or active_frame==e[1]:
     pending.pop(e[1],None);active_frame=None;waiting_until=0;busy=False
   elif e[0]=='peer':
    frame=pending.get(e[1])
    if frame:pending[e[1]]=(e[2],frame[1])
   elif e[0]=='error':status.set(e[1])
   elif e[0]=='sent':
    if e[2]==1:last_sequence.pop(e[4],None)
    else:
     # A fast result may reach the queue before the upload worker reports its
     # final ACK. Do not restart a completed frame's wait or overwrite it.
     if active_frame!=e[1] or e[1] not in pending:continue
     waiting_until=time.monotonic()+60
    status.set(f'帧 {e[1]}校验提交完成，上传 {e[3]:.2f}s；等待板端推理结果。' if e[2]==2 else f'模型上传并校验完成，用时 {e[3]:.2f}s。')
   elif e[0]=='result':
    source,r=e[1],e[2]
    frame=pending.get(r['frame_id'])
    if r['frame_id']!=active_frame or not frame or frame[0]!=source:continue
    if source in last_sequence and not 0<((r['sequence']-last_sequence[source])&0xffffffff)<0x80000000:continue
    last_sequence[source]=r['sequence'];pending.pop(r['frame_id'],None)
    busy=False;waiting_until=0;active_frame=None
    show(frame[1],r['boxes']);label='人脸出现' if r['event']&1 else '人脸离开' if r['event']&2 else '检测'
    line=f"帧 {r['frame_id']}：板端推理错误 {r['error']}" if r['error'] else f"帧 {r['frame_id']}：{label}，{len(r['boxes'])} 张人脸，板端 {r['duration_ms']}ms"
    status.set(line);history.insert('end',line+'\n');history.see('end');r['source']=source;log.write(json.dumps(r,ensure_ascii=False)+'\n');log.flush()
  if waiting_until and time.monotonic()>waiting_until:
   pending.pop(active_frame,None);active_frame=None;waiting_until=0;busy=False;status.set('等待板端结果超时，可重新送图。请检查板卡状态及 UDP 5002。')
  root.after(30,update)
 def close():stop.set();log.close();root.destroy()
 root.protocol('WM_DELETE_WINDOW',close);update();root.mainloop()
if __name__=='__main__':main()
