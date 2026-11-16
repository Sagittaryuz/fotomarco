// Toolbar/status overlay the preview; only capture controls reserve vertical space.
// Shared geometric plan for native UI and synthetic layout review. Not an iOS renderer.
export function cameraLayout(width:number,height:number,ratio:"4:3"|"16:9"="4:3") {
  if (!(width>0 && height>0)) throw new Error("Invalid camera viewport")
  const compact=height<500, toolbar=44, status=44, shutter=compact?56:76, mode=44
  const gap=4
  const available=Math.max(44,height-shutter-mode-gap*2)
  const aspect=width>height ? (ratio==="16:9"?16/9:4/3) : (ratio==="16:9"?9/16:3/4)
  const viewWidth=Math.min(width,available*aspect),viewHeight=viewWidth/aspect
  return {width,height,compact,toolbar,status,shutter,mode,gap,viewWidth,viewHeight,railHeight:Math.min(viewHeight-toolbar-status-16,180),railWidth:48}
}
