import {AbsoluteFill,Composition,registerRoot,Sequence} from 'remotion';
import {Video} from '@remotion/media';
import {staticFile} from 'remotion';
import {Backdrop} from './Backdrop';
import {Logo} from './scenes/Logo';
const Demo=()=> <AbsoluteFill><Backdrop/><Sequence durationInFrames={960}><div style={{position:'absolute',left:252,top:72,width:1416,height:936,borderRadius:18,overflow:'hidden'}}><Video src={staticFile('user-take-16s.mp4')} muted style={{width:'100%',height:'100%'}}/></div></Sequence><Sequence from={960} durationInFrames={240}><Logo/></Sequence></AbsoluteFill>;
registerRoot(()=> <><Composition id="Foundation-Evals" component={Demo} durationInFrames={1200} fps={60} width={1920} height={1080}/><Composition id="Logo-Outro" component={Logo} durationInFrames={240} fps={60} width={1920} height={1080}/><Composition id="Background" component={Backdrop} durationInFrames={1} fps={60} width={1920} height={1080}/></>);
