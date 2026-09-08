import {AbsoluteFill,Easing,Img,interpolate,staticFile,useCurrentFrame} from 'remotion';
import {Backdrop} from '../Backdrop';
const smooth={extrapolateLeft:'clamp',extrapolateRight:'clamp',easing:Easing.bezier(.22,1,.36,1)} as const;
export const Logo=()=>{const f=useCurrentFrame();return <AbsoluteFill style={{fontFamily:'Helvetica Neue,Arial,sans-serif',perspective:1400}}>
<Backdrop/>
<div style={{position:'absolute',left:252,top:72,width:1416,height:936,borderRadius:18,overflow:'hidden',opacity:interpolate(f,[0,42],[1,0],smooth),scale:interpolate(f,[0,42],[1,.98],smooth)}}><Img src={staticFile('user-last-frame.png')} style={{width:'100%',height:'100%'}}/></div>
<div style={{position:'absolute',left:780,top:285,width:360,height:360,borderRadius:82,overflow:'hidden',boxShadow:'0 24px 65px #356db32b',opacity:interpolate(f,[26,70],[0,1],smooth),transform:`translateY(${interpolate(f,[26,110],[45,0],smooth)}px) scale(${interpolate(f,[26,110],[.72,1],smooth)}) rotateY(${interpolate(f,[26,110],[-24,0],smooth)}deg)`}}><Img src={staticFile('app-logo.png')} style={{width:'100%',height:'100%',scale:1.12}}/><div style={{position:'absolute',inset:-150,background:'linear-gradient(115deg,transparent 40%,#ffffff70 49%,transparent 58%)',translate:`${interpolate(f,[90,165],[-650,650],smooth)}px 0`}}/></div>
<div style={{position:'absolute',top:700,width:'100%',textAlign:'center',fontSize:62,fontWeight:600,letterSpacing:-2,color:'#254266',opacity:interpolate(f,[68,115],[0,1],smooth),translate:`0 ${interpolate(f,[68,115],[15,0],smooth)}px`}}>Foundation Evals</div>
</AbsoluteFill>};
