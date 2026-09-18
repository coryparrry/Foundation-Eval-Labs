import { Video } from "@remotion/media";
import {
  AbsoluteFill,
  Composition,
  registerRoot,
  Sequence,
  staticFile,
} from "remotion";

import { Backdrop } from "./Backdrop";
import { Logo } from "./scenes/Logo";

const Demo = () => (
  <AbsoluteFill>
    <Backdrop />
    <Sequence durationInFrames={960}>
      <div
        style={{
          borderRadius: 18,
          height: 936,
          left: 252,
          overflow: "hidden",
          position: "absolute",
          top: 72,
          width: 1416,
        }}
      >
        <Video
          muted
          src={staticFile("user-take-16s.mp4")}
          style={{ height: "100%", width: "100%" }}
        />
      </div>
    </Sequence>
    <Sequence durationInFrames={240} from={960}>
      <Logo />
    </Sequence>
  </AbsoluteFill>
);

registerRoot(() => (
  <>
    <Composition
      component={Demo}
      durationInFrames={1200}
      fps={60}
      height={1080}
      id="Foundation-Evals"
      width={1920}
    />
    <Composition
      component={Logo}
      durationInFrames={240}
      fps={60}
      height={1080}
      id="Logo-Outro"
      width={1920}
    />
    <Composition
      component={Backdrop}
      durationInFrames={1}
      fps={60}
      height={1080}
      id="Background"
      width={1920}
    />
  </>
));
