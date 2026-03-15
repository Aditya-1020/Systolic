import os, sys
import numpy as np
try:
    import torch, torch.nn as nn, torch.optim as optim
    from torch.utils.data import DataLoader
    from torchvision import datasets, transforms
except ImportError:
    sys.exit("pip install torch torchvision")

N=4; DATA_WIDTH=8; ACCUM_WIDTH=48; NUM_EXPORT=32
OUT_DIR="tb/inference/inference_vectors"; EPOCHS=5; BATCH_SIZE=256; LR=1e-3
os.makedirs(OUT_DIR, exist_ok=True)

def fmt(val, wb): return f"{int(val)&((1<<wb)-1):0{wb//4}X}"
def write_hex(path, vals, wb):
    open(path,"w").writelines(fmt(int(v),wb)+"\n" for v in vals)
    print(f"  {path}  ({len(vals)} entries)")
def clamp8(x): return int(np.clip(round(x),-128,127))
def quantize(M, scale): return np.vectorize(clamp8)(np.array(M,dtype=np.float32)/scale).astype(np.int8)
def sym_scale(t): m=np.max(np.abs(t)); return float(m)/127.0 if m>0 else 1.0

class TinyCNN(nn.Module):
    def __init__(self):
        super().__init__()
        self.conv1=nn.Conv2d(1,8,3,bias=True); self.pool=nn.MaxPool2d(2)
        self.fc1=nn.Linear(8*13*13,64,bias=True); self.fc2=nn.Linear(64,10,bias=True)
        self.relu=nn.ReLU()
    def forward(self,x):
        x=self.relu(self.conv1(x)); x=self.pool(x)
        x=x.flatten(1); x=self.relu(self.fc1(x)); return self.fc2(x)

print("\nTraining")
T=transforms.Compose([transforms.ToTensor(),transforms.Normalize((0.1307,),(0.3081,))])
train_ds=datasets.MNIST("./data",train=True, download=True,transform=T)
test_ds =datasets.MNIST("./data",train=False,download=True,transform=T)
device="cuda" if torch.cuda.is_available() else "cpu"
model=TinyCNN().to(device)
opt=optim.Adam(model.parameters(),lr=LR)
loss_fn=nn.CrossEntropyLoss()
for ep in range(1,EPOCHS+1):
    model.train(); tl=0
    for xb,yb in DataLoader(train_ds,BATCH_SIZE,shuffle=True,num_workers=0):
        xb,yb=xb.to(device),yb.to(device); opt.zero_grad()
        l=loss_fn(model(xb),yb); l.backward(); opt.step(); tl+=l.item()
    print(f"  epoch {ep}/{EPOCHS}  loss={tl/len(DataLoader(train_ds,BATCH_SIZE)):.4f}")
model.eval()
float_acc=sum((model(xb.to(device)).argmax(1)==yb.to(device)).sum().item()
              for xb,yb in DataLoader(test_ds,BATCH_SIZE))/len(test_ds)
print(f"  Float accuracy: {float_acc*100:.2f}%")
torch.save(model.state_dict(),os.path.join(OUT_DIR,"model_float.pt"))

print("\nCalibration")
calib_inputs = {'img':[], 'conv_out':[], 'fc1_in':[], 'fc1_out':[]}
hooks = []
def hook_conv_in(m,inp,out):  calib_inputs['img'].append(inp[0].detach().cpu())
def hook_conv_out(m,inp,out): calib_inputs['conv_out'].append(out.detach().cpu())
def hook_fc1_in(m,inp,out):   calib_inputs['fc1_in'].append(inp[0].detach().cpu())
def hook_fc1_out(m,inp,out):  calib_inputs['fc1_out'].append(out.detach().cpu())
hooks.append(model.conv1.register_forward_hook(hook_conv_in))
hooks.append(model.conv1.register_forward_hook(hook_conv_out))
hooks.append(model.fc1.register_forward_hook(hook_fc1_in))
hooks.append(model.fc1.register_forward_hook(hook_fc1_out))
with torch.no_grad():
    n=0
    for xb,_ in DataLoader(train_ds,128,shuffle=True,num_workers=0):
        model(xb.to(device)); n+=len(xb)
        if n>=512: break
for h in hooks: h.remove()

img_tensor    = torch.cat(calib_inputs['img'])
fc1_in_tensor = torch.cat(calib_inputs['fc1_in'])
fc1_out_tensor= torch.cat(calib_inputs['fc1_out'])

# per-layer input scales (symmetric, derived from calibration)
s_img    = sym_scale(img_tensor.numpy())
s_conv_w = sym_scale(model.conv1.weight.data.cpu().numpy())
s_fc1_in = sym_scale(fc1_in_tensor.numpy())   # input to fc1 after pool
s_fc1_w  = sym_scale(model.fc1.weight.data.cpu().numpy())
s_fc1_out= sym_scale(np.maximum(0, fc1_out_tensor.numpy()))  # post-relu
s_fc2_w  = sym_scale(model.fc2.weight.data.cpu().numpy())

print(f"  s_img={s_img:.4f}  s_conv_w={s_conv_w:.4f}")
print(f"  s_fc1_in={s_fc1_in:.4f}  s_fc1_w={s_fc1_w:.4f}")
print(f"  s_fc1_out={s_fc1_out:.4f}  s_fc2_w={s_fc2_w:.4f}")

print("\n INT8 Quantization")
w_conv1=model.conv1.weight.data.cpu().numpy()
b_conv1=model.conv1.bias.data.cpu().numpy()
w_fc1  =model.fc1.weight.data.cpu().numpy()
b_fc1  =model.fc1.bias.data.cpu().numpy()
w_fc2  =model.fc2.weight.data.cpu().numpy()
b_fc2  =model.fc2.bias.data.cpu().numpy()

wq_conv1=quantize(w_conv1, s_conv_w)
wq_fc1  =quantize(w_fc1,   s_fc1_w)
wq_fc2  =quantize(w_fc2,   s_fc2_w)

# Bias scale = weight_scale * input_scale
bq_conv1=np.round(b_conv1/(s_conv_w*s_img   )).astype(np.int32)
bq_fc1  =np.round(b_fc1  /(s_fc1_w *s_fc1_in)).astype(np.int32)
bq_fc2  =np.round(b_fc2  /(s_fc2_w *s_fc1_out)).astype(np.int32)

print(f"  wq_fc1 [{wq_fc1.min()},{wq_fc1.max()}]  wq_fc2 [{wq_fc2.min()},{wq_fc2.max()}]")
wq_conv1_2d=wq_conv1.reshape(8,9)

print("\nExporting weights")

def export_tiled(mat, name):
    rows,cols=mat.shape
    M=np.pad(mat,((0,(N-rows%N)%N),(0,(N-cols%N)%N)),constant_values=0)
    PR,PC=M.shape; entries=[]
    for tr in range(PR//N):
        for tc in range(PC//N):
            blk=M[tr*N:(tr+1)*N,tc*N:(tc+1)*N]
            for r in range(N):
                entries.append(sum((int(blk[r,c])&0xFF)<<(c*DATA_WIDTH) for c in range(N)))
    write_hex(os.path.join(OUT_DIR,f"{name}.hex"),entries,N*DATA_WIDTH)

export_tiled(wq_conv1_2d,"wq_conv1_tiled")
export_tiled(wq_fc1,     "wq_fc1_tiled")
export_tiled(wq_fc2,     "wq_fc2_tiled")
write_hex(os.path.join(OUT_DIR,"wq_conv1_flat.hex"),wq_conv1_2d.flatten().tolist(),DATA_WIDTH)
write_hex(os.path.join(OUT_DIR,"wq_fc1_flat.hex"),  wq_fc1.flatten().tolist(),     DATA_WIDTH)
write_hex(os.path.join(OUT_DIR,"wq_fc2_flat.hex"),  wq_fc2.flatten().tolist(),     DATA_WIDTH)
write_hex(os.path.join(OUT_DIR,"bq_fc1.hex"),bq_fc1.tolist(),32)
write_hex(os.path.join(OUT_DIR,"bq_fc2.hex"),bq_fc2.tolist(),32)
np.save(os.path.join(OUT_DIR,"scales.npy"),
        np.array([s_conv_w,s_fc1_w,s_fc2_w,s_img,s_fc1_in,s_fc1_out]))

print("\nExporting test images")

for xb,yb in DataLoader(test_ds,NUM_EXPORT,shuffle=False):
    test_images,test_labels=xb[:NUM_EXPORT].numpy(),yb[:NUM_EXPORT].numpy(); break
np.save(os.path.join(OUT_DIR,"img_scale.npy"),np.array([s_img]))
write_hex(os.path.join(OUT_DIR,"tv_images.hex"),
          quantize(test_images.reshape(NUM_EXPORT,-1),s_img).flatten().tolist(),DATA_WIDTH)
write_hex(os.path.join(OUT_DIR,"gold_labels.hex"),test_labels.tolist(),8)

print("\nGolden model")

def relu(x):
    return np.maximum(0,x)

def im2col(img,k=3):
    H,W=img.shape; oh,ow=H-k+1,W-k+1
    cols=np.zeros((oh*ow,k*k),dtype=np.int32)
    for i in range(oh):
        for j in range(ow): cols[i*ow+j]=img[i:i+k,j:j+k].flatten()
    return cols
def maxpool2d(x,s=2):
    C,H,W=x.shape; return x.reshape(C,H//s,s,W//s,s).max(axis=(2,4))

def run_inference(img_raw):
    img_q = quantize(img_raw, s_img)
    col = im2col(img_q.astype(np.int32))
    conv_out = np.zeros((8,26,26), dtype=np.int32)
    for f in range(8):
        conv_out[f] = (col @ wq_conv1_2d[f].astype(np.int32) + bq_conv1[f]).reshape(26,26)
    conv_out = relu(conv_out)

    pool_out = maxpool2d(conv_out)
    flat_f32 = pool_out.flatten().astype(np.float32) * (s_conv_w * s_img)
    flat_q   = quantize(flat_f32, s_fc1_in)

    fc1_out  = wq_fc1.astype(np.int32) @ flat_q.astype(np.int32) + bq_fc1
    fc1_relu = relu(fc1_out)

    fc1_f32  = fc1_relu.astype(np.float32) * (s_fc1_w * s_fc1_in)
    fc1_q    = quantize(fc1_f32, s_fc1_out)
    fc2_out  = wq_fc2.astype(np.int32) @ fc1_q.astype(np.int32) + bq_fc2

    return flat_q, fc1_q, fc2_out

correct_q=0; gold_logits_all=[]; fc1_q_img0=None

for idx in range(NUM_EXPORT):
    flat_q, fc1_q, fc2_out = run_inference(test_images[idx,0])
    if idx==0: fc1_q_img0=fc1_q
    gold_logits_all.append(fc2_out.tolist())
    if int(np.argmax(fc2_out))==test_labels[idx]: correct_q+=1
int8_acc=correct_q/NUM_EXPORT
print(f"  INT8 accuracy: {int8_acc*100:.1f}%  (float: {float_acc*100:.2f}%)")
write_hex(os.path.join(OUT_DIR,"gold_fc2_logits.hex"),[v for l in gold_logits_all for v in l],ACCUM_WIDTH)
write_hex(os.path.join(OUT_DIR,"gold_preds.hex"),[int(np.argmax(l)) for l in gold_logits_all],8)

print("\nStaggered FC2 vectors")

def stagger_rows(M):
    r=[[0]*N for _ in range(2*N-1)]
    for i in range(N):
        for k in range(N): r[i+k][i]=int(M[i][k])
    return r

def stagger_cols(M):
    r=[[0]*N for _ in range(2*N-1)]
    for c in range(N):
        for k in range(N): r[c+k][c]=int(M[k][c])
    return r

wq_fc2_pad=np.pad(wq_fc2,((0,2),(0,0)),constant_values=0)
fc1_q = fc1_q_img0

with open(os.path.join(OUT_DIR,"sv_fc2_a.hex"),"w") as fa, \
     open(os.path.join(OUT_DIR,"sv_fc2_b.hex"),"w") as fb, \
     open(os.path.join(OUT_DIR,"sv_fc2_gold.hex"),"w") as fg:
    for rt in range(wq_fc2_pad.shape[0]//N):
        for ct in range(64//N):
            A=wq_fc2_pad[rt*N:(rt+1)*N, ct*N:(ct+1)*N].astype(np.int8)
            B=np.tile(fc1_q[ct*N:(ct+1)*N].reshape(N,1),(1,N)).astype(np.int8)
            C=A.astype(np.int64)@B.astype(np.int64)
            as_=stagger_rows(A); bs_=stagger_cols(B)
            for t in range(2*N-1):
                pa=pb=0
                for lane in range(N):
                    pa|=(int(as_[t][lane])&0xFF)<<(lane*DATA_WIDTH)
                    pb|=(int(bs_[t][lane])&0xFF)<<(lane*DATA_WIDTH)
                fa.write(f"{pa:0{N*DATA_WIDTH//4}X}\n")
                fb.write(f"{pb:0{N*DATA_WIDTH//4}X}\n")
            for r in range(N):
                for c in range(N): fg.write(fmt(int(C[r,c]),ACCUM_WIDTH)+"\n")

for f in ["sv_fc2_a.hex","sv_fc2_b.hex","sv_fc2_gold.hex"]:
    print(f"  {f}: {len(open(os.path.join(OUT_DIR,f)).readlines())} lines")

print(f"\nDone — Float: {float_acc*100:.2f}%  INT8: {int8_acc*100:.1f}%")