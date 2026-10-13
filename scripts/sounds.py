#!/usr/bin/env python3
"""Generate original deterministic prototype SFX with only Python's standard library."""
import array, math, pathlib, random, sys, wave
out = pathlib.Path(sys.argv[1]); out.mkdir(parents=True, exist_ok=True)
RATE = 22050

def save(name, samples):
    # Smooth endpoints and cap every source well below digital full scale.
    samples = list(samples)
    for i in range(min(180, len(samples)//2)):
        samples[i] *= i/180
        samples[-1-i] *= i/180
    peak = max(abs(x) for x in samples) or 1
    scale = min(1, .8/peak)
    pcm = array.array('h', (int(max(-1,min(1,x*scale))*32767) for x in samples))
    if sys.byteorder != 'little': pcm.byteswap()
    with wave.open(str(out / (name+'.wav')), 'wb') as f:
        f.setparams((1,2,RATE,0,'NONE','not compressed')); f.writeframes(pcm.tobytes())

for kind, length, variants in [('shot',.32,4),('explosion',1.25,4),('collapse',1.7,3),('rubble',.55,3),('glass',.65,3),('step',.13,4)]:
    for variant in range(variants):
        rng=random.Random(kind+str(variant)); low=0; samples=[]
        freq=65+variant*8
        for i in range(int(length*RATE)):
            t=i/RATE; noise=rng.uniform(-1,1); low=.92*low+.08*noise
            if kind=='shot': value=.58*noise*math.exp(-t*43)+.36*math.sin(2*math.pi*(155*t-95*t*t))*math.exp(-t*19)+low*.4*math.exp(-t*12)
            elif kind=='explosion': value=(low*2.3+math.sin(2*math.pi*(freq*t-12*t*t))*.3)*math.exp(-t*3.9)+noise*.23*math.exp(-t*34)
            elif kind=='collapse': value=(low*1.5+noise*.15)*(1-math.exp(-t*35))*math.exp(-t*2)*(0.65+.35*math.sin(t*42)**2)
            elif kind=='rubble': value=(low*.9+noise*.28)*math.exp(-t*9)*(0.4+.6*math.sin(t*(70+variant*8))**8)
            elif kind=='glass': value=sum(math.sin(2*math.pi*f*t)*math.exp(-t*(10+j*3)) for j,f in enumerate([1850+variant*130,2743,3921]))*.13+noise*.14*math.exp(-t*22)
            else: value=(low*.8+noise*.16)*math.exp(-t*36)
            samples.append(value)
        save(kind+str(variant),samples)

for name, frequencies in {'deploy':[440,660,880],'order':[760,1010],'cease':[550,330],'select':[880],'pause':[430,390],'reset':[330,550,660]}.items():
    samples=[]
    for frequency in frequencies:
        for i in range(int(.07*RATE)):
            t=i/RATE; env=math.sin(math.pi*t/.07)**2
            samples.append(.22*env*(math.sin(2*math.pi*frequency*t)+.18*math.sin(2*math.pi*frequency*2*t)))
    save(name+'0',samples)

# Supply plane flyover: a twin-prop drone that swells in, passes, and drops in pitch.
rng=random.Random('plane'); low=0; samples=[]; phase=0
length=4.2
for i in range(int(length*RATE)):
    t=i/RATE; x=(t-length*.55)/1.1
    swell=1/(1+x*x)
    freq=92*(1+.05*math.tanh(-x*1.6))
    phase+=2*math.pi*freq/RATE
    low=.95*low+.05*rng.uniform(-1,1)
    buzz=sum(math.sin(phase*h)/h for h in range(1,7))
    samples.append((.32*buzz*(.75+.25*math.sin(phase*.5))+low*.9)*swell)
save('plane0',samples)

# Strafing jet flyover: a turbofan whine over a roar that swells, passes, and Doppler-drops.
rng=random.Random('jet'); low=0; band=0; samples=[]; phase=0
length=4.4
for i in range(int(length*RATE)):
    t=i/RATE; x=(t-length*.5)/.7
    swell=1/(1+x*x)
    freq=1350*(1+.12*math.tanh(-x*1.4))
    phase+=2*math.pi*freq/RATE
    n=rng.uniform(-1,1); low=.9*low+.1*n; band=.6*band+.4*n
    samples.append((low*1.3+band*.35+.12*math.sin(phase)+.05*math.sin(phase*1.5))*swell)
save('jet0',samples)

# Rotary cannon burst: rounds at 65 Hz blur into a ripping drone, with a muzzle-blast tail.
rng=random.Random('gun'); low=0; samples=[]
length=1.1; burst=.55; rate=65
for i in range(int(length*RATE)):
    t=i/RATE; n=rng.uniform(-1,1); low=.85*low+.15*n
    pulse=math.exp(-((t*rate)%1)*5) if t < burst else 0
    tail=math.exp(-max(0,t-burst)*6)
    samples.append((pulse*(.7*n+.5*math.sin(2*math.pi*rate*t))+low*1.4)*tail*min(1,t*60))
save('gun0',samples)

# Circular crossfade makes the quiet wind/rain bed seamless rather than restarting.
rng=random.Random(173); low=0; raw=[]
for i in range(RATE*9):
    n=rng.uniform(-1,1); low=.994*low+.006*n
    raw.append(n*.075+low*.8)
overlap=RATE
bed=raw[overlap:]
for i in range(overlap):
    a=i/overlap
    bed[-overlap+i]=bed[-overlap+i]*(1-a)+raw[i]*a
# No endpoint envelope on loops: the wrapped signal is already continuous.
pcm=array.array('h',(int(x*32767) for x in bed))
if sys.byteorder!='little': pcm.byteswap()
with wave.open(str(out/'ambient0.wav'),'wb') as f:
    f.setparams((1,2,RATE,0,'NONE','not compressed'));f.writeframes(pcm.tobytes())
print(f'Generated {len(list(out.glob("*.wav")))} original sound assets.')
