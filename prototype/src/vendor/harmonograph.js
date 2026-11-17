/* Shared by Max v8, the editor, and the verification suite. No clocks or randomness. */
(function (root, factory) {
  const api = factory();
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  root.HG = api;
})(typeof globalThis !== 'undefined' ? globalThis : this, function () {
  'use strict';
  const TAU = Math.PI * 2;
  const clamp = (x, lo, hi) => Math.max(lo, Math.min(hi, Number.isFinite(+x) ? +x : lo));
  const mod = (x, m) => ((x % m) + m) % m;
  const gcd = (a, b) => b ? gcd(b, a % b) : a;
  const lcm = (a, b) => Math.min(1048576, a / gcd(a, b) * b);
  const copy = x => JSON.parse(JSON.stringify(x));
  const COLORS = ['#F2D16B','#A992E8','#58C4DD','#E07FC4','#9BCB6E','#F0A15E','#EE7D6E','#3FB8A6'];
  const NOTES = ['C','C♯','D','E♭','E','F','F♯','G','A♭','A','B♭','B'];
  const SCALES = {
    'Major':[0,2,4,5,7,9,11], 'Minor':[0,2,3,5,7,8,10], 'Dorian':[0,2,3,5,7,9,10],
    'Mixolydian':[0,2,4,5,7,9,10], 'Lydian':[0,2,4,6,7,9,11], 'Phrygian':[0,1,3,5,7,8,10],
    'Locrian':[0,1,3,5,6,8,10], 'Harmonic Minor':[0,2,3,5,7,8,11],
    'Melodic Minor':[0,2,3,5,7,9,11], 'Minor Pentatonic':[0,3,5,7,10],
    'Major Pentatonic':[0,2,4,7,9], 'Whole Tone':[0,2,4,6,8,10], 'Chromatic':[0,1,2,3,4,5,6,7,8,9,10,11]
  };
  const param = (key, label, value, min, max, step=1, detents=[]) => ({key,label,value,min,max,step,detents});
  const modulus = () => param('m','m',7,2,32,1,[5,7,8,12,16]);
  const waveParams = () => [param('cycles','k',1,0.25,16,.25,[1,2,3,4,8]),param('phase','φ',0,0,1,.01,[0,.25,.5,.75]),param('depth','a',1,0,2,.01),param('offset','c',0,-1,1,.01)];
  const cache = new Map();
  function memo(key, factory) { if (!cache.has(key)) { if(cache.size>256) cache.clear(); cache.set(key,factory()); } return cache.get(key); }
  function popcount(n){let c=0;for(n=n>>>0;n;n>>>=1)c+=n&1;return c;}
  function digits(n,b){let c=0;while(n>0){c+=n%b;n=Math.floor(n/b);}return c;}
  function ruler(n){let c=0;for(n=Math.max(1,Math.floor(n));n%2===0;n/=2)c++;return c;}
  const streams=new Map();
  function* stream(kind,p){
    const a=[],seen=new Set([0]),primes=[];let x=.217,y=.1,z=.1,row=1n<<31n,candidate=2;
    if(kind==='kolakoski'){a.push(1,2,2);yield 1;yield 2;yield 2;for(let k=2;;k++){const v=a[a.length-1]===1?2:1;for(let j=0;j<a[k];j++){a.push(v);yield v;}}}
    for(let i=0;;i++){
      let v=0;
      if(kind==='primes'||kind==='primegaps'){
        while(primes.length<i+(kind==='primegaps'?2:1)){let ok=true;for(const q of primes){if(q*q>candidate)break;if(candidate%q===0){ok=false;break;}}if(ok)primes.push(candidate);candidate++;}
        v=kind==='primes'?primes[i]%p.m:primes[i+1]-primes[i];
      }else if(kind==='fibonacci')v=i<2?i:(a[i-1]+a[i-2])%p.m;
      else if(kind==='lucas')v=i<2?[2,1][i]%p.m:(a[i-1]+a[i-2])%p.m;
      else if(kind==='tribonacci')v=i<3?[0,0,1][i]:(a[i-1]+a[i-2]+a[i-3])%p.m;
      else if(kind==='recaman'){v=i?a[i-1]-i:0;if(v<0||seen.has(v))v=i?a[i-1]+i:0;seen.add(v);}
      else if(kind==='stern')v=i<2?i:i%2?a[(i-1)/2]+a[(i+1)/2]:a[i/2];
      else if(kind==='logistic'){x=p.r*x*(1-x);v=x;}
      else if(kind==='circle'){x=mod(x+p.omega-p.K/TAU*Math.sin(TAU*x),1);v=x;}
      else if(kind==='tent'){x=p.r*(x<.5?x:1-x);v=x;}
      else if(kind==='sinemap'){x=p.r*Math.sin(Math.PI*x);v=x;}
      else if(kind==='henon'){const nx=1-p.a*x*x+y;y=p.b*x;x=clamp(nx,-3,3);v=clamp((x+1.5)/3,0,1);}
      else if(kind==='lorenz'||kind==='rossler'){
        for(let k=0;k<8;k++){let dx,dy,dz;if(kind==='lorenz'){dx=p.sigma*(y-x);dy=x*(p.rho-z)-y;dz=x*y-p.beta*z;}else{dx=-y-z;dy=x+p.a*y;dz=p.b+z*(x-p.c);}x+=dx*.005;y+=dy*.005;z+=dz*.005;if(!Number.isFinite(x+y+z)||Math.abs(x+y+z)>1e5){x=.1;y=.1;z=.1;}}
        v=clamp(kind==='lorenz'?(x+25)/50:(x+15)/30,0,1);
      }else if(kind==='ca'){
        v=Number((row>>BigInt(p.cell))&1n);let next=0n;for(let j=0;j<64;j++){const pat=Number((row>>BigInt((j+1)%64))&1n)*4+Number((row>>BigInt(j))&1n)*2+Number((row>>BigInt((j+63)%64))&1n);if((p.rule>>pat)&1)next|=1n<<BigInt(j);}row=next;
      }
      a.push(v);yield v;
    }
  }
  function sequence(kind,p,len=4096){
    if(['digits','collatz','lsystem'].includes(kind))return memo(kind+JSON.stringify(p),()=>{
      let a=[],x,word='A';
      if(kind==='lsystem'){for(let i=0;i<Math.min(p.depth||12,16);i++)word=word.replace(/A|B/g,c=>c==='A'?'AB':'A');return [...word].map(c=>c==='A'?1:0);}
      if(kind==='digits'){
        // Fixed-point digit streams, 100 decimal places; explicit finite cycle, never fake endless precision.
        const strings=['31415926535897932384626433832795028841971693993751058209749445923078164062862089986280348253421170679','27182818284590452353602874713526624977572470936999595749669676277240766303535475945713821785251664274','14142135623730950488016887242096980785696718753769480731766797379907324784621070388503875343276415727','16180339887498948482045868343656381177203091798057628621354486227052604628189024497072072041893911374'];
        let s=strings[p.constant||0], den=10n**BigInt(s.length-1),num=BigInt(s)%den,b=BigInt(p.base||7);
        for(let i=0;i<96;i++){num*=b;a.push(Number(num/den));num%=den;}return a;
      }
      if(kind==='collatz'){x=p.s||22;for(let i=0;i<8192;i++){a.push(x);if(x===1)break;x=x%2?3*x+1:x/2;if(!Number.isSafeInteger(x))break;}return a;}

    });
    const key=kind+JSON.stringify(p);let entry=streams.get(key);
    if(!entry){if(streams.size>=16)streams.delete(streams.keys().next().value);entry={values:[],iterator:stream(kind,p)};streams.set(key,entry);}
    while(entry.values.length<len)entry.values.push(entry.iterator.next().value);
    return entry.values;
  }
  const catalogue=[];
  const controls=[];
  for(const [field,label,min,max]of [['amplitude','a',-2,2],['ratio','k',.125,16],['phase','φ',0,1]])for(let i=0;i<8;i++)controls.push({name:label+(i+1),path:'terms.'+i+'.'+field,min,max});
  controls.push(...[
    {name:'Root',path:'root',global:true,enum:NOTES.map((_,i)=>i),labels:NOTES},
    {name:'Scale',path:'scale',global:true,enum:Object.keys(SCALES)},
    {name:'Degree',path:'degree',global:true,min:0,max:6,integer:true},
    {name:'Extension',path:'extension',global:true,min:0,max:4,integer:true},
    {name:'Tempo',path:'tempo',global:true,min:20,max:300},
    {name:'Chord source',path:'chordSource',global:true,enum:['pads','progression','formula']},
    {name:'Section',action:'recall',min:0,max:7,integer:true},
    {name:'Build hold',action:'build',min:0,max:1,integer:true},
    {name:'Sum on',path:'sumEnabled',enum:[false,true],labels:['Off','On']},
    {name:'Gate formula',path:'gate',formulas:true},
    {name:'Velocity formula',path:'velocity',formulas:true},
    {name:'Channel type',path:'type',enum:['Melody','Bass','Chord','Drums']},
    {name:'Active',action:'active',min:0,max:1,integer:true},
    {name:'Commit 4 bars',action:'commit',min:0,max:1,integer:true},
    {name:'Store section',action:'store',min:0,max:1,integer:true},
    {name:'Panic',action:'panic',min:0,max:1,integer:true}
  ]);
  function add(id,name,category,formula,params,fn,period=null,integer=false){catalogue.push({id,name,category,formula,params,fn,period,integer});}
  const seq = (id,p,n) => {const finite=['digits','lsystem'].includes(id),at=Math.max(0,Math.floor(n));const a=sequence(id,p,finite?4096:Math.max(256,at+1));return a[finite?mod(at,a.length):at]||0;};
  for(const id of ['fibonacci','lucas','tribonacci'])add(id,({fibonacci:'Fibonacci mod m',lucas:'Lucas mod m',tribonacci:'Tribonacci mod m'})[id],'Number sequences',id==='tribonacci'?'Tₙ = (Tₙ₋₁ + Tₙ₋₂ + Tₙ₋₃) mod m':'Fₙ = (Fₙ₋₁ + Fₙ₋₂) mod m',[modulus()],(n,p)=>seq(id,p,n),null,true);
  add('squares','Squares mod m','Number sequences','n² mod m',[modulus()],(n,p)=>mod(n*n,p.m),p=>p.m,true);
  add('triangular','Triangular numbers','Number sequences','n(n + 1) / 2 mod m',[modulus()],(n,p)=>mod(n*(n+1)/2,p.m),p=>2*p.m,true);
  add('cubes','Cubes mod m','Number sequences','n³ mod m',[modulus()],(n,p)=>mod(n*n*n,p.m),p=>p.m,true);
  add('linear','Modular walk','Number sequences','(a·n + c) mod m',[param('a','a',2,1,16),param('c','c',0,0,31),modulus()],(n,p)=>mod(p.a*n+p.c,p.m),p=>p.m/gcd(p.a,p.m),true);
  add('powers','Powers mod p','Number sequences','aⁿ mod p',[param('a','a',3,1,16),modulus()],(n,p)=>{let r=1,b=p.a;for(let k=n;k>0;k=Math.floor(k/2)){if(k%2)r=r*b%p.m;b=b*b%p.m;}return r;},null,true);
  add('collatz','Collatz from s','Number sequences','c ↦ c/2 (even), 3c + 1 (odd)',[param('s','start s',22,1,9999),param('after','after 1',1,0,2)],(n,p)=>{let a=sequence('collatz',p);return n<a.length?a[n]:p.after===0?1:p.after===1?a[n%a.length]:[4,2,1][(n-a.length)%3];},null,true);
  add('recaman','Recamán','Number sequences','aₙ = aₙ₋₁ − n if new ≥ 0; else +n',[],(n,p)=>seq('recaman',p,n),null,true);
  add('norgard','Nørgård infinity series','Number sequences','a₂ₙ = −aₙ ; a₂ₙ₊₁ = aₙ + 1',[],n=>{const f=k=>k===0?0:k%2?f((k-1)/2)+1:-f(k/2);return f(n);},null,true);
  add('popcount','Binary digit sum','Number sequences','Σ bits(n)',[param('bits','bits',8,1,20)],(n,p)=>popcount(n%(2**p.bits)),p=>2**p.bits,true);
  add('digitsum','Base-b digit sum','Number sequences','Σ digitsᵦ(n)',[param('base','b',3,2,16)],(n,p)=>digits(n,p.base),null,true);
  add('thue','Thue–Morse','Number sequences','popcount(n) mod 2',[],n=>popcount(n)%2,null,true);
  add('ruler','Ruler sequence','Number sequences','ν₂(n + 1)',[],n=>ruler(n+1),null,true);
  add('stern','Stern’s diatomic','Number sequences','s₂ₙ = sₙ ; s₂ₙ₊₁ = sₙ + sₙ₊₁',[],(n,p)=>seq('stern',p,n),null,true);
  add('kolakoski','Kolakoski','Number sequences','1, 2, 2, 1, 1, 2, …',[],(n,p)=>seq('kolakoski',p,n),null,true);
  add('beatty','Beatty / Fibonacci word','Number sequences','⌊(n+1)α⌋ − ⌊nα⌋',[param('alpha','α',1.61803398875,1,3,.001,[1.5,1.61803398875,2.41421356])],(n,p)=>Math.floor((n+1)*p.alpha)-Math.floor(n*p.alpha),null,true);
  add('digits','Irrational digit stream','Number sequences','digitsᵦ(π, e, √2, φ) · 96-digit cycle',[param('constant','constant',0,0,3),param('base','b',7,2,16)],(n,p)=>seq('digits',p,n),()=>96,true);
  add('primes','Primes mod m','Number sequences','pₙ mod m',[modulus()],(n,p)=>seq('primes',p,n),null,true);
  add('primegaps','Prime gaps','Number sequences','pₙ₊₁ − pₙ',[],(n,p)=>seq('primegaps',p,n),null,true);
  add('divisors','Divisor count','Number sequences','d(n + 1)',[],n=>{let c=0;for(let i=1;i*i<=n+1;i++)if((n+1)%i===0)c+=i*i===n+1?1:2;return c;},null,true);
  add('totient','Euler totient','Number sequences','φ(n + 1)',[],n=>{let v=n+1,r=v;for(let p=2;p*p<=v;p++)if(v%p===0){while(v%p===0)v/=p;r-=r/p;}if(v>1)r-=r/v;return r;},null,true);
  add('vdc','Van der Corput','Number sequences','radical inverseᵦ(n)',[param('base','b',2,2,12)],(n,p)=>{let v=0,d=1;while(n){d*=p.base;v+=(n%p.base)/d;n=Math.floor(n/p.base);}return v;});
  add('gray','Gray-code bit','Number sequences','bitₖ(n ⊕ (n ≫ 1))',[param('bit','k',2,0,12)],(n,p)=>((n^(n>>1))>>p.bit)&1,p=>2**(p.bit+2),true);
  add('bytebeat','Bytebeat','Number sequences','(n·(n≫a | n≫b)) & mask',[param('a','a',3,0,12),param('b','b',5,0,12),param('mask','mask',31,1,255)],(n,p)=>(n*(n>>p.a|n>>p.b))&p.mask,null,true);
  add('logistic','Logistic map','Dynamical systems','x ↦ r·x(1 − x)',[param('r','r',3.83,2.5,3.99,.001,[2.9,3.2,3.5,3.55,3.83,3.95])],(n,p)=>seq('logistic',p,n+256));
  add('circle','Circle map','Dynamical systems','θ ↦ θ + Ω − K sin(2πθ) / 2π',[param('omega','Ω',.333333333,0,1,.001,[.25,1/3,.4,.5,.6666667]),param('K','K',.8,0,2,.01)],(n,p)=>seq('circle',p,n));
  add('tent','Tent map','Dynamical systems','x ↦ r·min(x, 1 − x)',[param('r','r',1.9,1,1.999,.001)],(n,p)=>seq('tent',p,n));
  add('sinemap','Sine map','Dynamical systems','x ↦ r sin(πx)',[param('r','r',.9,.5,1,.001)],(n,p)=>seq('sinemap',p,n));
  add('henon','Hénon map','Dynamical systems','x ↦ 1 − ax² + y ; y ↦ bx',[param('a','a',1.4,.8,1.4,.001),param('b','b',.3,.1,.3,.001)],(n,p)=>seq('henon',p,n));
  add('lorenz','Lorenz attractor','Dynamical systems','ẋ = σ(y−x), ẏ = x(ρ−z)−y, ż = xy−βz',[param('sigma','σ',10,5,15,.1),param('rho','ρ',28,15,35,.1),param('beta','β',8/3,2,4,.01)],(n,p)=>seq('lorenz',p,n));
  add('rossler','Rössler attractor','Dynamical systems','ẋ = −y−z, ẏ = x+ay, ż = b+z(x−c)',[param('a','a',.2,.1,.3,.01),param('b','b',.2,.1,.3,.01),param('c','c',5.7,4,7,.1)],(n,p)=>seq('rossler',p,n));
  add('ca','Cellular automaton','Dynamical systems','cellᵢ(rule, n)',[param('rule','rule',90,0,255,1,[30,90,110]),param('cell','cell',31,0,63)],(n,p)=>seq('ca',p,n),null,true);
  add('lsystem','L-system','Dynamical systems','A → AB, B → A',[param('depth','depth',10,2,16)],(n,p)=>seq('lsystem',p,n),p=>sequence('lsystem',p).length,true);
  for(const id of ['sine','triangle','saw','square'])add(id,id[0].toUpperCase()+id.slice(1)+' contour','Geometry & waves',({sine:'a sin(2πkn/P + φ) + c',triangle:'a tri(kn/P + φ) + c',saw:'a saw(kn/P + φ) + c',square:'a sign(sin(2πkn/P + φ)) + c'})[id],waveParams(),(n,p,P)=>{let t=mod(n/P*p.cycles+p.phase,1);let v=id==='sine'?Math.sin(TAU*t):id==='triangle'?1-4*Math.abs(t-.5):id==='saw'?2*t-1:t<.5?1:-1;return clamp((v*p.depth+p.offset+1)/2,0,1);},(p,P)=>sampledPeriod(P/p.cycles));
  add('lissajous','Lissajous p:q','Geometry & waves','x = sin(pθ), y = sin(qθ + φ)',[param('p','p',3,1,12),param('q','q',2,1,12),param('phase','φ',.25,0,1,.01)],(n,p,P)=>Math.hypot(Math.sin(TAU*n/P*p.p),Math.sin(TAU*n/P*p.q+TAU*p.phase))/Math.SQRT2,(p,P)=>P);
  add('rose','Rose curve','Geometry & waves','r = |cos(kθ)|',[param('k','k',5,1,16)],(n,p,P)=>Math.abs(Math.cos(p.k*TAU*n/P)),(p,P)=>P);
  add('superformula','Superformula','Geometry & waves','r = (|cos(mφ/4)|ⁿ² + |sin(mφ/4)|ⁿ³)⁻¹/ⁿ¹',[param('m','m',5,2,16,.1),param('n1','n₁',.4,.2,8,.05),param('n2','n₂',1.7,.2,8,.05),param('n3','n₃',1.7,.2,8,.05)],(n,p,P)=>clamp(Math.pow(Math.abs(Math.cos(p.m*TAU*n/P/4))**p.n2+Math.abs(Math.sin(p.m*TAU*n/P/4))**p.n3,-1/p.n1),0,2)/2,(p,P)=>P);
  add('spirograph','Spirograph','Geometry & waves','(R−r)eⁱᶿ + de⁻ⁱ⁽ᴿ⁻ʳ⁾ᶿ/ʳ',[param('R','R',5,2,16),param('r','r',3,1,15),param('d','d',2,0,10,.1)],(n,p,P)=>{let a=TAU*n/P,d=p.R-p.r,x=d*Math.cos(a)+p.d*Math.cos(d*a/p.r),y=d*Math.sin(a)-p.d*Math.sin(d*a/p.r);return Math.hypot(x,y)/Math.max(1,Math.abs(d)+p.d);},(p,P)=>P*p.r/gcd(p.R,p.r));
  add('polygon','Star polygon','Geometry & waves','vertex(nq mod p) · {p/q}',[param('p','p',7,3,16),param('q','q',2,1,15)],(n,p)=>mod(n*p.q,p.p),p=>p.p/gcd(p.p,p.q),true);
  add('vertices','Rotating vertices','Geometry & waves','cos(2πn·speed / sides)',[param('sides','sides',5,3,16),param('speed','speed',1,1,8)],(n,p)=>(Math.cos(TAU*n*p.speed/p.sides)+1)/2,p=>p.sides/gcd(p.sides,p.speed));
  add('polynomial','Polynomial','Geometry & waves','ax³ + bx² + cx',[param('a','a',1,-3,3,.01),param('b','b',0,-3,3,.01),param('c','c',-1,-3,3,.01)],(n,p,P)=>{let x=2*mod(n,P)/P-1;return clamp((p.a*x**3+p.b*x*x+p.c*x+1)/2,0,1);},(p,P)=>P);
  add('times','Times-table circle','Geometry & waves','m·n mod N',[param('m','m',2,1,24),param('N','N',12,2,64)],(n,p)=>mod(p.m*n,p.N),p=>p.N/gcd(p.m,p.N),true);
  add('cardioid','Cardioid','Geometry & waves','r = 1 − cos θ',[],(n,p,P)=>(1-Math.cos(TAU*n/P))/2,(p,P)=>P);
  add('astroid','Astroid','Geometry & waves','x = cos³θ, y = sin³θ',[],(n,p,P)=>Math.hypot(Math.cos(TAU*n/P)**3,Math.sin(TAU*n/P)**3),(p,P)=>P);
  add('spiral','Archimedean spiral','Geometry & waves','r = θ / 2π',[],(n,p,P)=>mod(n,P)/P,(p,P)=>P);
  add('butterfly','Butterfly','Geometry & waves','r = eᶜᵒˢᶿ − 2cos(4θ) + sin⁵(θ/12)',[],(n,p,P)=>{let t=TAU*n/P;return clamp((Math.exp(Math.cos(t))-2*Math.cos(4*t)+Math.sin(t/12)**5+2)/6,0,1);},(p,P)=>P*12);
  add('harmonograph','Harmonograph','Geometry & waves','sin(pθ)e⁻ᵈᶿ + sin(qθ+φ)e⁻ᵈᶿ',[param('p','p',2,1,8),param('q','q',3,1,8),param('decay','d',.02,0,.2,.005),param('phase','φ',.25,0,1,.01)],(n,p,P)=>{let t=TAU*mod(n,P)/P;return .5+.25*(Math.sin(p.p*t)+Math.sin(p.q*t+TAU*p.phase))*Math.exp(-p.decay*t);},(p,P)=>P);
  add('groove','Genre groove','Rhythm & gates','g(n; genre, voice, density, rotation)',[param('genre','Genre',0,0,10),param('voice','Drum',0,0,7),param('density','Density',1,0,2,.05),param('rotation','Rotation',0,0,31)],(n,p)=>grooveValue(n,p),p=>groovePattern(p).n);
  add('euclid','Euclidean E(k,n,r)','Rhythm & gates','E(k, n, rotation)',[param('k','k',5,0,32),param('n','n',16,1,32,1,[8,12,16,24,32]),param('rot','rot',0,0,31)],(n,p)=>euclid(n,p.k,p.n,p.rot),p=>p.n,true);
  add('modgate','Modulo gate','Rhythm & gates','n mod d = 0',[param('d','d',2,1,32),param('rot','rot',0,0,31)],(n,p)=>mod(n-p.rot,p.d)===0?1:0,p=>p.d,true);
  add('staircase','Floor staircase','Rhythm & gates','⌊(q+1)k/n⌋ − ⌊qk/n⌋',[param('k','k',5,0,32),param('n','n',8,1,32)],(n,p)=>Math.floor((n+1)*p.k/p.n)-Math.floor(n*p.k/p.n),p=>p.n,true);
  add('bit','Binary-count bit','Rhythm & gates','(n ≫ k) & 1',[param('bit','k',2,0,12)],(n,p)=>(n>>p.bit)&1,p=>2**(p.bit+1),true);
  add('polymeter','Polymeter','Rhythm & gates','(n mod a = 0) ∨ (n mod b = 0)',[param('a','a',3,1,16),param('b','b',4,1,16)],(n,p)=>n%p.a===0||n%p.b===0?1:0,p=>lcm(p.a,p.b),true);
  add('zeno','Zeno roll','Rhythm & gates','tₖ = L(1 − qᵏ)',[param('q','q',.8,.4,.95,.01,[.5,.8]),param('L','L',16,4,64)],(n,p)=>{for(let k=0;k<64;k++)if(Math.floor(p.L*(1-p.q**k))===mod(n,p.L))return 1;return 0;},p=>p.L,true);
  add('circlechord','Diatonic circle','Harmony','degree = 3n mod 7',[],n=>mod(3*n,7),()=>7,true);
  add('extension','Extension ladder','Harmony','stack = 3 + n mod 5',[],n=>n%5,()=>5,true);
  add('voicelead','Voice-leading walk','Harmony','inversion = n mod voices',[param('voices','voices',3,3,7)],(n,p)=>n%p.voices,p=>p.voices,true);
  add('spread','Spread / strum','Harmony','spread = ½ + ½ sin(2πn/P)',[],(n,p,P)=>(Math.sin(TAU*n/P)+1)/2,(p,P)=>P);
  add('plr','Neo-Riemannian P/L/R','Harmony','P: parallel · L: leading-tone · R: relative',[param('move','move',0,0,2)],(n,p)=>n%2?[0,4,9][p.move]:0,()=>2,true);
  add('accent','Metric accent mask','Expression','1 on beat, ½ on eighth, ¼ elsewhere',[],n=>n%4===0?1:n%2===0?.55:.25,()=>4);
  add('crescendo','Crescendo ramp','Expression','v = (n mod L) / (L − 1)',[param('length','L',32,2,128)],(n,p)=>mod(n,p.length)/(p.length-1),p=>p.length);
  const byId=Object.fromEntries(catalogue.map(f=>[f.id,f]));
  const mathControls=['pitch','gate','velocity'].flatMap(stage=>catalogue.flatMap(f=>f.params.map(p=>({stage,formula:f.id,param:p,name:stage+' '+f.name+' '+p.key}))));
  function defaults(id){return Object.fromEntries((byId[id]||byId.fibonacci).params.map(p=>[p.key,p.value]));}
  function cleanParams(id,params={}){return Object.fromEntries((byId[id]||byId.fibonacci).params.map(p=>{let v=clamp(params[p.key]??p.value,p.min,p.max);return[p.key,p.step===1?Math.round(v):v];}));}
  function value(id,n,params={},P=16){const f=byId[id]||byId.fibonacci,p=cleanParams(f.id,params),at=n<0?mod(n,Math.max(1,P)):n;return f.fn(f.category==='Geometry & waves'&&!f.integer?at:Math.floor(at),p,Math.max(1,P));}
  function normal(id,n,p={},P=16){const f=byId[id]||byId.fibonacci,v=value(f.id,n,p,P);if(!f.integer)return clamp(v,0,1);const m=p.m||p.N||p.p||(f.category==='Rhythm & gates'||['thue','gray','ca','lsystem'].includes(f.id)?2:8);return clamp(mod(v,m)/Math.max(1,m-1),0,1);}
  function sampledPeriod(q){for(let d=1;d<=256;d++)if(Math.abs(q*d-Math.round(q*d))<1e-7)return Math.round(q*d);return null;}
  function period(id,p={},P=16){const f=byId[id]||byId.fibonacci; p=cleanParams(f.id,p);if(id==='fibonacci'||id==='lucas'){let a=id==='lucas'?2%p.m:0,b=1;const ia=a;for(let i=1;i<=p.m*p.m*6;i++){[a,b]=[b,(a+b)%p.m];if(a===ia&&b===1)return i;}}if(id==='collatz')return sequence(id,p).length;if(id==='logistic'){let a=sequence(id,p);for(let q of [1,2,3,4,6,8,12,16,32,64]){let ok=true;for(let i=3000;i<3100;i++)if(Math.abs(a[i]-a[i-q])>1e-7){ok=false;break;}if(ok)return q;}return null;}return f.period?Math.max(1,f.period(p,P)):null;}
  function euclid(step,k,n,rot=0){n=Math.max(1,Math.round(n));k=Math.round(clamp(k,0,n));return mod((step-rot)*k,n)<k?1:0;}
  function lane(name,note,k,n=16,rot=0){return {name,note,mute:false,gate:'euclid',params:{k,n,rot},velocity:'accent',velocityParams:{},accent:100,ghost:35,micro:0,logic:'none',other:0,approach:false,anticipation:false};}
  const GENRES={
    House:[[4,16,0],[2,16,4],[8,16,2],[4,16,2]], 'Lo-fi 80':[[3,16,0],[2,16,4],[7,16,0],[3,16,2]],
    'Boom bap':[[3,16,0],[2,16,4],[8,16,0],[2,16,7]],Trap:[[3,16,0],[1,16,8],[12,16,0],[3,16,3]],
    Drill:[[5,32,0],[2,32,8],[11,32,0],[3,16,5]],'Jersey club':[[5,16,0],[4,16,2],[8,16,0],[3,8,0]],
    Dancehall:[[3,8,0],[2,16,4],[8,16,0],[5,16,3]],Reggaeton:[[4,16,0],[5,16,2],[8,16,0],[3,8,0]],
    Jungle:[[7,32,0],[4,32,4],[14,32,0],[5,16,2]],Rock:[[2,8,0],[2,8,2],[8,16,0],[1,16,0]],
    'Funk / disco':[[4,16,0],[2,16,4],[13,16,0],[5,16,2]]
  };
  function groovePattern(p){const g=Object.values(GENRES)[Math.round(p.genre)]||GENRES.House,voice=Math.round(p.voice),spec=voice===0?g[0]:voice===1||voice===4?g[1]:voice===2?g[2]:voice===5?g[3]:voice===3?[4,16,2]:voice===6?[2,16,5]:[1,32,0];return {k:Math.round(clamp(spec[0]*p.density,0,spec[1])),n:spec[1],rotation:spec[2]+p.rotation};}
  function grooveValue(n,p){const pattern=groovePattern(p),at=Math.floor(n)-pattern.rotation;if(!euclid(n,pattern.k,pattern.n,pattern.rotation))return 0;return mod(at,16)===0?1:mod(at,4)===0?.88:mod(at,2)===0?.76:.64;}
  function channel(i){let type=['Melody','Melody','Bass','Chord','Drums','Melody','Melody','Melody'][i];let formula=['fibonacci','collatz','sine','extension','euclid','thue','rose','lorenz'][i];return {
    id:i,name:['Lead','Fall','808','Keys','Kit','Counter','Arp','Pad'][i],color:COLORS[i],type,formula,params:defaults(formula),active:i<5,queued:null,solo:false,
    rate:type==='Bass'?1:type==='Chord'?4:.25,cycle:16,phase:0,swing:.5,micro:0,gate:'euclid',gateParams:{k:16,n:16,rot:0},gateLength:.72,
    velocity:'accent',velocityParams:{},accent:100,ghost:45,repeated:'retrigger',low:type==='Bass'?33:57,high:type==='Bass'?57:81,
    gravity:.4,palette:2,mode:i===1?'step':'absolute',fold:'reflect',leap:2,recovery:true,contour:0,shape:'arch',phrase:16,cadence:true,
    variation:0,variationParam:'m',octave:0,glide:0,glideMethod:'cc',rootAnchor:true,octavePattern:0,invert:false,retrograde:false,speed:1,
    sumEnabled:false,sumGate:false,sumVelocity:false,sumThreshold:.5,sumMode:'contour',sumMod:7,ratioSnap:true,terms:Array.from({length:8},(_,j)=>({amplitude:j===0?1:j===1?.5:0,formula:'sine',params:defaults('sine'),ratio:j*2+1,phase:0,operator:'+',source:-1})),
    extension:0,inversion:0,minimal:true,spread:0,strum:0,strumDirection:1,voicingFormula:true,followContour:false,drumLane:null,drumFormula:false,drumThreshold:.5,drumVelocity:'legacy',pitchRoot:null,octaveRadius:null,
    lanes:[lane('Kick',36,4),lane('Snare',38,2,16,4),lane('Closed hat',42,8),lane('Open hat',46,3,16,2),lane('Clap',39,2,16,4),lane('Perc',45,5,8),lane('Rim',37,3,16,1),lane('Crash',49,1,32)].map((l,j)=>({...l,mute:j>3})),
    destination:'Live track '+(i+1),ccEnabled:false,ccNumber:74,ccLow:0,ccHigh:127,ccFormula:'sine'
  };}
  function initialState(){const s={version:1,tempo:132,root:9,scale:'Minor',degree:0,chordRoot:null,borrowed:'',quality:'diatonic',extension:0,inversion:0,spread:0,chordOctave:0,shift:false,staticMode:true,escape:false,
    chordSource:'progression',progression:[0,5,2,6],chordFormula:'circlechord',chordParams:{},chordRate:4,allowed:[0,1,2,3,4,5,6],quantize:'bar',phrase:16,
    selected:0,scene:'Stack',style:'3B1B',section:'Drop',queuedSection:null,build:{held:false,released:false,start:0,end:null,q:.8,gap:1,hits:32,bars:4,target:'bar',riser:.8,cc:74,muteKick:true,muteBass:true,density:true},channels:Array.from({length:8},(_,i)=>channel(i)),sections:[]};
    for(const [name,active]of [['Intro',[0,3]],['Verse',[0,2,4]],['Pre',[0,1,3,4]],['Build',[0,1,3,4]],['Drop',[0,1,2,3,4]],['Break',[1,4]],['Drop 2',[0,1,2,3,4,5,6]],['Outro',[1,3]]]){let snapshot=sectionSnapshot(s);snapshot.channels.forEach((c,i)=>c.active=active.includes(i));s.sections.push({name,snapshot});}return s;
  }
  function degreeMidi(d,s){let sc=SCALES[s.scale]||SCALES.Minor;return s.root+12*Math.floor(d/sc.length)+sc[mod(d,sc.length)];}
  function chordAt(s,beat){const sc=SCALES[s.scale]||SCALES.Minor;let degree=s.degree;
    if(s.chordSource==='progression')degree=s.progression[mod(Math.floor(beat/s.chordRate),s.progression.length)];
    if(s.chordSource==='formula'&&s.chordFormula!=='plr'){let n=Math.floor(beat/s.chordRate),a=s.allowed.length?s.allowed:[0];degree=a[mod(Math.floor(value(s.chordFormula,n,s.chordParams)),a.length)];}
    let pcs=[0,2,4,6,8,10,12].slice(0,3+s.extension).map(d=>mod(degreeMidi(degree+d,s),12));
    const borrow={'♭II':[1,[0,4,7]],'♭III':[3,[0,4,7]],'♭VI':[8,[0,4,7]],'♭VII':[10,[0,4,7]],iv:[5,[0,3,7]],'V/V':[2,[0,4,7,10]],'V/vi':[4,[0,4,7,10]],TT:[1,[0,4,7,10]],sus:[sc[mod(degree,sc.length)],[0,5,7]]};
    let root=mod(degreeMidi(degree,s),12);if(s.borrowed&&borrow[s.borrowed]&&s.escape){const b=borrow[s.borrowed];root=mod(s.root+b[0],12);pcs=b[1].map(p=>mod(root+p,12));}
    if(s.quality!=='diatonic'){let ints=({major:[0,4,7,11,14,17,21],minor:[0,3,7,10,14,17,21],dominant:[0,4,7,10,14,17,21],diminished:[0,3,6,9,14,17,20]})[s.quality]||[0,4,7];pcs=ints.slice(0,3+s.extension).map(p=>mod(root+p,12));}
    if(s.chordSource==='formula'&&s.chordFormula==='plr'&&Math.floor(beat/s.chordRate)%2){const minor=mod(pcs[1]-root,12)===3,move=cleanParams('plr',s.chordParams).move;root=mod(root+(minor?[0,-4,3]:[0,4,-3])[move],12);pcs=(minor?[0,4,7,11,14,17,21]:[0,3,7,10,14,17,21]).slice(0,3+s.extension).map(p=>mod(root+p,12));}
    if(s.chordSource==='pads'&&s.chordRoot!=null&&s.escape){root=mod(s.chordRoot,12);pcs=(s.quality==='minor'?[0,3,7,10,14,17,21]:[0,4,7,10,14,17,21]).slice(0,3+s.extension).map(p=>mod(root+p,12));}
    if(s.shift){if(pcs.length>1)pcs[1]=mod(root+5,12);if(pcs.length>3)pcs[3]=mod(root+10,12);}
    // Explicit chromatic escape controls whether requested borrowed/altered voices may leave the scale.
    if(!s.escape)pcs=pcs.map(p=>nearestPC(p,sc.map(v=>mod(s.root+v,12))));
    return {degree,root,pcs:[...new Set(pcs)],name:NOTES[root]+(mod(pcs[1]-root,12)===3?'m':'')+(['','7','9','11','13'][s.extension]||'')};
  }
  function nearestPC(p,pcs){return pcs.reduce((a,b)=>Math.min(mod(p-a,12),mod(a-p,12))<=Math.min(mod(p-b,12),mod(b-p,12))?a:b,pcs[0]);}
  function scaleNotes(c,s){let out=[];for(let n=Math.ceil(clamp(c.low+c.octave*12,0,127));n<=clamp(c.high+c.octave*12,0,127);n++)if((SCALES[s.scale]||SCALES.Minor).includes(mod(n-s.root,12)))out.push(n);return out;}
  function fold(d,len,mode,previous,octaveSize=7){if(len<=1)return 0;if(mode==='wrap')return mod(d,len);if(mode==='nearest'){let k=mod(d,octaveSize),a=[];for(let i=0;i<len;i++)if(i%octaveSize===k)a.push(i);return a.length?a.reduce((x,y)=>Math.abs(x-previous)<=Math.abs(y-previous)?x:y):clamp(d,0,len-1);}let t=mod(d,2*(len-1));return t<len?t:2*(len-1)-t;}
  function sumValue(c,n,s,visited=new Set()){
    if(visited.has(c.id))return normal(c.formula,n,c.params,c.cycle);visited=new Set(visited);visited.add(c.id);
    let out=0,weight=0,first=true;
    for(const t of c.terms.slice(0,8)){if(!t.amplitude)continue;let at=n*t.ratio+t.phase*c.cycle;
      const integer=c.sumMode==='integer';
      const sample=q=>{const source=t.source>=0?s.channels[t.source]:null;if(!integer)return source?rawValue(source,q,s,visited):normal(t.formula,q,t.params,c.cycle);if(source?.sumEnabled)return Math.round(rawValue(source,q,s,visited)*(c.sumMod-1));const id=source?.formula||t.formula,p=source?.params||t.params,cycle=source?.cycle||c.cycle;return byId[id].integer?value(id,q,p,cycle):Math.round(normal(id,q,p,cycle)*(c.sumMod-1));};
      let v=integer?sample(at):sample(at)*2-1,a=t.amplitude;
      if(first||t.operator==='+')out+=a*v;
      else if(t.operator==='×')out*=a*v;
      else if(t.operator==='∘')out=integer?a*sample(out):a*(sample((out+1)*c.cycle/2)*2-1);
      else if(t.operator==='mod')out=mod(out+a*v,c.sumMod);
      else if(t.operator==='interleave'){if(n%2)out=a*v;}
      else if(t.operator==='mask')out=sample(at)>(integer?0:.5)?out:0;
      else if(t.operator==='max')out=Math.max(out,a*v);else if(t.operator==='min')out=Math.min(out,a*v);
      else if(t.operator==='AND')out=out>0&&v>0?1:(integer?0:-1);else if(t.operator==='OR')out=out>0||v>0?1:(integer?0:-1);else if(t.operator==='XOR')out=(out>0)!==(v>0)?1:(integer?0:-1);
      weight+=Math.abs(a);first=false;
    }
    if(!weight)return .5;
    return c.sumMode==='integer'?mod(Math.round(out),c.sumMod)/Math.max(1,c.sumMod-1):clamp((out/weight+1)/2,0,1);
  }
  function rawValue(c,n,s,visited){let at=n*c.speed+c.phase;if(c.retrograde)at=c.cycle-1-mod(at,c.cycle);let p={...c.params};let variant=[0,1,0,2][mod(Math.floor(n/c.phrase),4)];if(c.variation&&Object.prototype.hasOwnProperty.call(p,c.variationParam))p[c.variationParam]+=variant*c.variation;
    let v=c.sumEnabled?sumValue(c,at,s,visited):normal(c.formula,at,p,c.cycle);return c.invert?1-v:v;
  }
  function gateValue(id,n,p){return value(id,n,p)>0?1:0;}
  function laneHit(l,n,lanes){let at=n+(l.anticipation?2:0),hit=gateValue(l.gate,at,l.params);if(l.approach)hit=hit||gateValue(l.gate,at+1,l.params);if(l.logic!=='none'){const b=lanes[clamp(l.other,0,lanes.length-1)],other=gateValue(b.gate,at,b.params);if(l.logic==='AND')hit=hit&&other;if(l.logic==='OR')hit=hit||other;if(l.logic==='XOR')hit=!!hit!==!!other;if(l.logic==='NOT')hit=hit&&!other;}return !!hit;}
  function drumSample(c,l,n,s){const value=rawValue(c,n,s),hit=value>0&&value>=clamp(c.drumThreshold,0,1),velocity=c.drumVelocity==='formula'?Math.round(clamp(l.ghost+(l.accent-l.ghost)*value,1,127)):c.drumVelocity==='fixed'?Math.round(clamp(l.accent,1,127)):vel(l,n);return {value,hit,velocity};}
  function vel(c,n){return Math.round(clamp(c.ghost+(c.accent-c.ghost)*normal(c.velocity,n,c.velocityParams,c.phrase||16),1,127));}
  function buildProgress(s,beat){return s.build.held||s.build.released?clamp((beat-s.build.start)/(s.build.bars*4),0,1):0;}
  function compileChannel(s,index,startBeat=0,bars=4){
    const c=s.channels[index],end=startBeat+bars*4,events=[],notes=scaleNotes(c,s),rate=clamp(c.rate,.0625,16),startN=Math.max(0,Math.floor(startBeat/rate)),endN=Math.ceil(end/rate);
    if(c.type!=='Drums'&&!notes.length)return events;
    // Phrase-local integration provides deterministic seeking without a hidden random-walk state.
    let previous=0,prevLeap=0,lastChord=[];const beginN=Math.floor(startN/Math.max(1,c.phrase))*c.phrase;
    const solo=s.channels.some(c=>c.solo),enabled=c.active&&(!solo||c.solo);
    const append=(pitch,n,beat,duration,velocity,extra={})=>{if(beat>=startBeat-1e-8&&beat<end-1e-8&&enabled)events.push({pitch:Math.round(clamp(pitch,0,127)),velocity:Math.round(clamp(velocity,1,127)),beat,duration:Math.max(.01,duration),step:n,...extra});};
    for(let n=beginN;n<endN;n++){
      if(n%c.phrase===0)lastChord=[];
      let beat=n*rate,now=chordAt(s,beat),phase=mod(n,c.phrase)/Math.max(1,c.phrase-1),shape=c.shape==='arch'?Math.sin(Math.PI*phase):c.shape==='ramp'?phase:.5;
      let v=rawValue(c,n,s)*(1-c.contour)+shape*c.contour;let degree;
      if(c.mode==='step'){if(n%c.phrase===0){previous=Math.floor(notes.length/2);prevLeap=0;}let jump=Math.round((v*2-1)*c.leap);if(c.recovery&&Math.abs(prevLeap)>2)jump=-Math.sign(prevLeap);degree=previous+jump;prevLeap=jump;}else degree=Math.round(v*(notes.length-1));
      if(c.fold==='drift')degree+=Math.round(Math.sin(n/c.phrase/4*TAU)*3);
      degree=fold(degree,notes.length,c.fold,previous,(SCALES[s.scale]||SCALES.Minor).length);previous=degree;
      const weight=n%16===0?1:n%4===0?.75:n%2===0?.5:.25;
      let allowed=notes;
      if(c.palette===0||c.gravity>0&&weight>=1-c.gravity*.75)allowed=notes.filter(p=>now.pcs.includes(p%12));
      else if(c.palette===1){let pent=[0,2,4,7,9];if(s.scale.toLowerCase().includes('minor'))pent=[0,3,5,7,10];allowed=notes.filter(p=>pent.includes(mod(p-s.root,12)));}
      let pitch=notes[degree];if(allowed.length)pitch=allowed.reduce((a,b)=>Math.abs(a-pitch)<=Math.abs(b-pitch)?a:b);
      if(c.palette===3&&s.escape&&n%2===1)pitch=clamp(pitch+(n%4===1?1:-1),c.low,c.high);
      if(c.cadence&&n%c.phrase===c.phrase-1){let a=notes.filter(p=>p%12===now.root);if(a.length)pitch=a.reduce((a,b)=>Math.abs(a-pitch)<=Math.abs(b-pitch)?a:b);}
      let delay=(n%2?(c.swing-.5)*rate*2:0)+c.micro*s.tempo/60000;
      const building=(s.build.held||s.build.released)&&beat>=s.build.start&&(s.build.end===null||beat<s.build.end);
      if(c.type==='Drums'){
        c.lanes.forEach((l,li)=>{if(c.drumLane!=null&&li!==c.drumLane||l.mute||building&&s.build.muteKick&&li===0)return;let ll=l;if(building&&s.build.density&&li===2&&l.gate==='euclid')ll={...l,params:{...l.params,k:Math.round(l.params.k+(l.params.n-l.params.k)*buildProgress(s,beat))}};
          if(c.drumFormula&&c.drumLane!=null){const sample=drumSample(c,ll,n,s);if(sample.hit)append(l.note,n,beat+delay+l.micro*s.tempo/60000,rate*c.gateLength,sample.velocity,{lane:li,formulaValue:sample.value});return;}
          if(laneHit(ll,n,c.lanes)&&(!c.sumGate||sumValue(c,n,s)>=c.sumThreshold))append(l.note,n,beat+delay+l.micro*s.tempo/60000,rate*c.gateLength,c.sumVelocity?l.ghost+(l.accent-l.ghost)*sumValue(c,n,s):vel(l,n),{lane:li});});
      }else if(c.sumGate?sumValue(c,n,s)>=c.sumThreshold:gateValue(c.gate,n,c.gateParams)){
      if(c.type==='Bass'){if(building&&s.build.muteBass)continue;if(c.rootAnchor){let a=notes.filter(p=>p%12===now.root);if(a.length)pitch=a[0];}if(c.octavePattern&&euclid(n,c.octavePattern,8)&&notes.includes(pitch+12))pitch+=12;}
        if(c.type==='Chord'){
          let ext=c.voicingFormula?Math.floor(v*4):c.extension,cs=chordAt({...s,extension:ext},beat),ps=[];
          cs.pcs.forEach(pc=>{let p=c.low+mod(pc-c.low,12);ps.push(p);});ps.sort((a,b)=>a-b);
          if(c.followContour){const shift=12*Math.round((pitch-ps[0])/12);ps=ps.map(p=>p+shift);}
          let inv=mod(c.inversion+s.inversion+(c.voicingFormula?Math.floor(v*3):0),Math.max(1,ps.length));for(let i=0;i<inv;i++)ps.push(ps.shift()+12);
          ps=ps.map((p,i)=>clamp(p+(i%2?Math.round(c.spread)*12:0)+12*(s.chordOctave||0),0,127));
          if(c.minimal&&!c.followContour&&lastChord.length)ps=ps.map((p,i)=>{let a=[p-12,p,p+12].filter(p=>p>=c.low&&p<=c.high);return a.length?a.reduce((x,y)=>Math.abs(x-lastChord[i%lastChord.length])<=Math.abs(y-lastChord[i%lastChord.length])?x:y):p;});
          ps=ps.map(p=>{while(p>c.high&&p-12>=c.low)p-=12;while(p<c.low&&p+12<=c.high)p+=12;let bounded=clamp(p,c.low,c.high);if(!s.escape&&!notes.includes(bounded))bounded=notes.reduce((a,b)=>Math.abs(a-bounded)<=Math.abs(b-bounded)?a:b);return bounded;});ps=[...new Set(ps)];lastChord=ps;
          if(c.strumDirection<0)ps.reverse();ps.forEach((p,i)=>append(p,n,beat+delay+i*c.strum*s.tempo/60000,rate*c.gateLength,c.sumVelocity?Math.round(c.ghost+(c.accent-c.ghost)*sumValue(c,n,s)):vel(c,n)));
        }else append(pitch,n,beat+delay,rate*c.gateLength,c.sumVelocity?Math.round(c.ghost+(c.accent-c.ghost)*sumValue(c,n,s)):vel(c,n));
      }
    }
    if(c.type==='Drums'&&(c.drumLane==null||c.drumLane===1)&&(s.build.held||s.build.released)){
      let b=s.build,L=b.bars*4,t=0;for(let k=0;k<b.hits;k++){t=b.start+Math.min(L,b.gap*(1-b.q**k)/(1-b.q));if(b.end!==null&&t>=b.end)break;append(38,k,t,.04,70+Math.round(50*clamp((t-b.start)/L,0,1)),{lane:1,roll:true});}
    }
    events.sort((a,b)=>a.beat-b.beat||a.pitch-b.pitch);
    const out=[],lastByPitch=new Map();
    for(const e of events){let prev=lastByPitch.get(e.pitch);if(c.type!=='Drums'&&prev&&e.beat<=prev.beat+prev.duration+rate*(1-c.gateLength)+1e-6){if(c.repeated==='tie'){prev.duration=e.beat+e.duration-prev.beat;continue;}if(c.repeated==='suppress')continue;prev.duration=Math.min(prev.duration,Math.max(.01,e.beat-prev.beat-.002));}out.push(e);lastByPitch.set(e.pitch,e);}
    return out;
  }
  function boundary(s,beat){const q=s.quantize==='beat'?1:s.quantize==='phrase'?s.phrase/4:4;return (Math.floor(beat/q+1e-6)+1)*q;}
  // Resolve future section/mute/drop boundaries before handing events to Max's
  // scheduler. UI polling must never decide the musical dispatch time.
  function compileTimeline(s,index,start=0,bars=4){
    const end=start+bars*4,work=copy(s),cuts=[start,end];
    for(const c of work.channels)if(c.queued&&c.queued.beat>start&&c.queued.beat<end)cuts.push(c.queued.beat);
    if(work.queuedSection&&work.queuedSection.beat>start&&work.queuedSection.beat<end)cuts.push(work.queuedSection.beat);
    if(work.build.released&&work.build.end>start&&work.build.end<end)cuts.push(work.build.end);
    const points=[...new Set(cuts)].sort((a,b)=>a-b),out=[];
    for(let i=0;i<points.length-1;i++){applyPending(work,points[i]);for(const e of compileChannel(work,index,points[i],(points[i+1]-points[i])/4))out.push({...e,duration:Math.min(e.duration,points[i+1]-e.beat)});}
    return out;
  }
  function sumPeriod(c,s,seen=new Set()){
    if(seen.has(c.id))return null;seen=new Set(seen);seen.add(c.id);let result=1;
    for(const t of c.terms.filter(t=>t.amplitude)){
      const source=t.source>=0?s.channels[t.source]:null,p=source?(source.sumEnabled?sumPeriod(source,s,seen):period(source.formula,source.params,source.cycle)):period(t.formula,t.params,c.cycle);
      if(!p||!Number.isFinite(t.ratio)||!t.ratio)return null;
      const q=p/Math.abs(t.ratio);let den=1;while(den<=64&&Math.abs(q*den-Math.round(q*den))>1e-6)den++;if(den>64)return null;
      result=lcm(result,Math.round(q*den));if(result>=1048576)return null;
    }return result;
  }
  function ratioChoices(c,t,s){
    const source=t.source>=0?s.channels[t.source]:null,p=source?(source.sumEnabled?sumPeriod(source,s):period(source.formula,source.params,source.cycle)):period(t.formula,t.params,c.cycle);
    if(!p||!Number.isInteger(p))return Array.from({length:16},(_,i)=>i+1);
    const choices=Array.from({length:16},(_,i)=>i+1).filter(k=>c.phrase%(p/gcd(p,k))===0);
    return choices.length?choices:Array.from({length:16},(_,i)=>i+1);
  }
  function playPads(s,index){const c=s.channels[index];
    if(c.type==='Drums')return Array.from({length:16},(_,i)=>{const l=c.lanes[c.drumLane==null?i:i===0?c.drumLane:-1];return l?{label:l.name,pitches:[l.note]}:{label:'—',pitches:[]};});
    if(c.type==='Chord'&&!s.staticMode)return Array.from({length:16},(_,i)=>{
      const pc=i%12,degree=SCALES[s.scale].indexOf(mod(pc-s.root,12)),chordRoot=degree<0?pc:null;
      if(degree<0&&!s.escape)return{label:NOTES[pc],pitches:[]};
      const cs=chordAt({...s,chordSource:'pads',degree:Math.max(0,degree),borrowed:'',chordRoot},0),pitches=[];
      for(const tone of cs.pcs){let n=c.low+mod(tone-c.low,12)+(i>=12?12:0);while(n>c.high)n-=12;if(n>=c.low)pitches.push(n);}
      return{label:NOTES[pc],degree:Math.max(0,degree),borrowed:'',chordRoot,pitches};
    });
    if(c.type==='Chord')return Array.from({length:16},(_,i)=>{const borrowed=['♭II','♭III','♭VI','♭VII','iv','V/V','V/vi','TT','sus'][i-7]||'',degree=i<7?i:s.degree,cs=chordAt({...s,chordSource:'pads',degree,borrowed,chordRoot:null},0),notes=s.escape?Array.from({length:Math.max(0,c.high-c.low+1)},(_,j)=>j+c.low):scaleNotes(c,s),pitches=cs.pcs.map(pc=>{const matches=notes.filter(n=>n%12===pc);return matches.length?matches[0]:null;}).filter(n=>n!==null);return {label:i<7?['I','II','III','IV','V','VI','VII'][i]:borrowed,degree,borrowed,pitches:borrowed&&!s.escape?[]:pitches};});
    const notes=scaleNotes(c,s);return Array.from({length:16},(_,i)=>{const note=notes[i];return note===undefined?{label:'—',pitches:[]}:{label:NOTES[note%12]+(Math.floor(note/12)-1),pitches:[note]};});
  }
  const sectionKeys=['channels','tempo','root','scale','degree','chordRoot','borrowed','quality','extension','inversion','spread','chordOctave','shift','staticMode','escape','chordSource','progression','chordFormula','chordParams','chordRate','allowed','phrase','build'];
  function sectionSnapshot(s){const out={};for(const key of sectionKeys)if(s[key]!==undefined)out[key]=copy(s[key]);out.channels.forEach(c=>c.queued=null);Object.assign(out.build,{held:false,released:false,start:0,end:null});return out;}
  function applyPending(s,beat){for(const c of s.channels)if(c.queued&&beat>=c.queued.beat){c.active=c.queued.active;c.queued=null;}if(s.queuedSection&&beat>=s.queuedSection.beat){let sec=s.sections.find(x=>x.name===s.queuedSection.name);if(sec){for(const k of sectionKeys)if(sec.snapshot[k]!==undefined)s[k]=copy(sec.snapshot[k]);s.section=sec.name;}s.queuedSection=null;}if(s.build.released&&beat>=s.build.end){s.build.held=false;s.build.released=false;s.build.end=null;}return s;}
  function command(s,cmd,beat=0,playing=false){
    if(cmd.type==='set'){let path=cmd.path.split('.');if(path.some(k=>['__proto__','constructor','prototype'].includes(k)))throw Error('Invalid path');let obj=s;for(const k of path.slice(0,-1)){if(obj[k]===undefined)throw Error('Unknown state path');obj=obj[k];}const k=path[path.length-1];if(!(k in obj)&&!['params','gateParams','velocityParams','chordParams'].some(v=>path.includes(v)))throw Error('Unknown setting');obj[k]=cmd.value;
      if(k==='formula'&&obj.params)obj.params=defaults(cmd.value);if(k==='ratio'){const channelIndex=Number(path[1]),channel=s.channels[channelIndex];obj.ratio=clamp(obj.ratio,.125,16);if(channel&&channel.ratioSnap)obj.ratio=ratioChoices(channel,obj,s).reduce((a,b)=>Math.abs(a-obj.ratio)<=Math.abs(b-obj.ratio)?a:b);}
      if(k==='gate'){if(obj.gateParams)obj.gateParams=defaults(cmd.value);else obj.params=defaults(cmd.value);}
      if(k==='velocity')obj.velocityParams=defaults(cmd.value);
      if(k==='chordFormula')s.chordParams=defaults(cmd.value);
      if(path[0]==='channels'&&k==='name'){obj.name=String(obj.name).slice(0,60);for(const sec of s.sections)if(sec.snapshot?.channels?.[Number(path[1])])sec.snapshot.channels[Number(path[1])].name=obj.name;}
    }else if(cmd.type==='range'){const c=s.channels[cmd.channel];c.low=Math.round(clamp(cmd.low??c.low,0,115));c.high=Math.min(127,c.low+12*clamp(cmd.octaves,1,6));if(c.type==='Chord')c.followContour=true;
    }else if(cmd.type==='toggle'){const c=s.channels[cmd.channel];if(playing)c.queued={active:c.queued?!c.queued.active:!c.active,beat:boundary(s,beat)};else c.active=!c.active;
    }else if(cmd.type==='recall'){if(playing)s.queuedSection={name:cmd.name,beat:boundary(s,beat)};else{s.queuedSection={name:cmd.name,beat:0};applyPending(s,0);}
    }else if(cmd.type==='store'){const name=String(cmd.name||s.section).slice(0,40);const sec={name,snapshot:sectionSnapshot(s)};let at=s.sections.findIndex(x=>x.name===name);if(at<0)s.sections.push(sec);else s.sections[at]=sec;
    }else if(cmd.type==='rename'){const sec=s.sections.find(x=>x.name===cmd.name);if(sec){sec.name=String(cmd.value).slice(0,40);if(s.section===cmd.name)s.section=sec.name;}
    }else if(cmd.type==='deleteSection')s.sections=s.sections.filter(x=>x.name!==cmd.name);
    else if(cmd.type==='build'){if(cmd.held){s.build.held=true;s.build.released=false;s.build.start=beat;s.build.end=null;}else{s.build.held=false;s.build.released=playing;s.build.end=playing?boundary({...s,quantize:s.build.target},beat):null;}}
    else if(cmd.type==='genre'){let c=s.channels[cmd.channel],g=GENRES[cmd.name];if(g)c.lanes.slice(0,4).forEach((l,i)=>{l.gate='euclid';l.params={k:g[i][0],n:g[i][1],rot:g[i][2]};l.mute=false;});}
    else if(cmd.type==='canon'){const src=s.channels[cmd.channel],i=clamp(cmd.target,0,s.channels.length-1),old=s.channels[i];s.channels[i]={...copy(src),id:i,name:old.name,color:old.color,phase:src.phase-(cmd.delay||4)};}
    else if(cmd.type==='preset')return preset(cmd.name,s);
    s.root=Math.round(clamp(s.root,0,11));s.tempo=clamp(s.tempo,20,999);s.extension=Math.round(clamp(s.extension,0,4));s.selected=Math.round(clamp(s.selected,0,Math.max(0,s.channels.length-1)));s.chordRate=clamp(s.chordRate,.25,64);s.degree=Math.round(clamp(s.degree,0,6));if(!SCALES[s.scale])s.scale='Minor';
    s.build.q=clamp(s.build.q,.05,.99);s.build.bars=clamp(s.build.bars,1,64);s.build.hits=Math.round(clamp(s.build.hits,1,256));s.build.gap=clamp(s.build.gap,.0625,16);
    for(const c of s.channels)if(c.type==='Drums'&&c.drumLane!=null&&c.lanes[c.drumLane]){c.formula=c.lanes[c.drumLane].gate;c.params=copy(c.lanes[c.drumLane].params);}
    for(const c of s.channels){c.low=Math.round(clamp(c.low,0,126));c.high=Math.round(clamp(c.high,c.low+1,127));c.params=cleanParams(c.formula,c.params);c.cycle=Math.round(clamp(c.cycle,1,4096));c.rate=clamp(c.rate,.0625,16);c.phrase=Math.round(clamp(c.phrase,1,256));c.gravity=clamp(c.gravity,0,1);c.contour=clamp(c.contour,0,1);c.gateLength=clamp(c.gateLength,.05,4);c.swing=clamp(c.swing,.5,.75);c.strum=clamp(c.strum,0,200);c.speed=clamp(c.speed,1/64,64);c.sumThreshold=clamp(c.sumThreshold??.5,0,1);c.sumMod=Math.round(clamp(c.sumMod,2,128));c.accent=clamp(c.accent,1,127);c.ghost=clamp(c.ghost,1,127);c.terms=c.terms.slice(0,8);for(const t of c.terms){t.amplitude=clamp(t.amplitude,-2,2);t.ratio=clamp(t.ratio,.125,16);t.phase=clamp(t.phase,0,1);t.source=Math.round(clamp(t.source,-1,s.channels.length-1));}}
    return s;
  }
  function preset(name,old){const s=initialState();if(old){s.tempo=old.tempo;s.root=old.root;s.scale=old.scale;}
    if(name==='Break'){s.channels.forEach((c,i)=>c.active=[1,4].includes(i));s.channels[4].lanes.forEach((l,i)=>l.mute=i!==5);s.section='Break';}
    if(name==='Formula Sum'){let c=s.channels[0];c.sumEnabled=true;c.terms[2]={...c.terms[2],amplitude:.3,formula:'fibonacci',params:{m:7},ratio:1};c.terms[3]={...c.terms[3],amplitude:.3,source:2,ratio:1};s.scene='Epicycles';}
    if(name==='Logistic journey'){s.channels[0].formula='logistic';s.channels[0].params=defaults('logistic');s.scene='Logistic';}
    if(name==='Harmony focus'){s.root=2;s.scale='Dorian';s.tempo=100;s.chordSource='formula';s.selected=3;s.scene='Pitch circle';}
    if(name==='Showpiece'){s.channels[0].formula='superformula';s.channels[0].params=defaults('superformula');s.channels[7].active=true;s.scene='Showpiece';}
    if(name==='All eight'){s.channels.forEach(c=>c.active=true);s.scene='Constellation';}return s;
  }
  function importState(input,withSections=true){
    if(!input||!Array.isArray(input.channels)||input.channels.length<1||input.channels.length>32)throw Error('A Harmonograph state needs 1–32 channels.');
    if(input.version!==undefined&&input.version!==1)throw Error('Unsupported state version.');
    const s=initialState();for(const key of Object.keys(s))if(input[key]!==undefined&&!['channels','sections','build'].includes(key))s[key]=copy(input[key]);
    s.build={...s.build,...input.build};
    s.channels=input.channels.map((v,i)=>{const c=channel(i%8);for(const key of Object.keys(c))if(v[key]!==undefined)c[key]=copy(v[key]);c.id=i;
      if(!byId[c.formula]||!byId[c.gate]||!byId[c.velocity])throw Error('Unknown formula on channel '+(i+1));
      c.gateParams=cleanParams(c.gate,c.gateParams);c.velocityParams=cleanParams(c.velocity,c.velocityParams);
      c.terms=Array.from({length:8},(_,j)=>({...channel(i%8).terms[j],...c.terms[j]}));for(const t of c.terms){if(!byId[t.formula])throw Error('Unknown sum formula');t.params=cleanParams(t.formula,t.params);}
      c.lanes=c.lanes.map((l,j)=>({...channel(i%8).lanes[j],...l}));return c;
    });
    if(withSections&&Array.isArray(input.sections))s.sections=input.sections.map(sec=>({name:String(sec.name).slice(0,40),snapshot:sectionSnapshot(importState(sec.snapshot,false))}));
    return command(s,{type:'validate'});
  }
  return {TAU,clamp,mod,gcd,lcm,copy,COLORS,NOTES,SCALES,controls,mathControls,catalogue,byId,defaults,cleanParams,value,normal,period,euclid,GENRES,channel,initialState,degreeMidi,chordAt,scaleNotes,fold,sumValue,sumPeriod,ratioChoices,rawValue,laneHit,drumSample,groovePattern,compileChannel,compileTimeline,playPads,boundary,applyPending,command,preset,buildProgress,importState};
});
