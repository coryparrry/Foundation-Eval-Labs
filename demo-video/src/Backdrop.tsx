import { AbsoluteFill, Img, staticFile } from "remotion";

export const Backdrop = () => (
  <AbsoluteFill>
    <Img
      src={staticFile("background.png")}
      style={{ height: "100%", objectFit: "cover", width: "100%" }}
    />
  </AbsoluteFill>
);
