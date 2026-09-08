import {AbsoluteFill,Img,staticFile} from 'remotion';
export const Backdrop=()=> <AbsoluteFill><Img src={staticFile('background.png')} style={{width:'100%',height:'100%',objectFit:'cover'}}/></AbsoluteFill>;
