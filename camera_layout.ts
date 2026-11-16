// Shared geometry; native UI and synthetic review use the same measurements.
// Portrait toolbar overlays the viewfinder; bottom controls remain outside it.
export function cameraLayout(width:number,height:number,ratio:"4:3"|"16:9"="4:3", overlayToolbar=true) {
  if (!(width>0 && height>0)) throw new Error("Invalid camera viewport")
  const landscape=width>height, compact=height<500, toolbar=44, status=44, shutter=compact?56:76, mode=44, gap=4
  const captureWidth=landscape ? Math.min(188,width*.28) : Math.min(width-32,380)
  const contentWidth=landscape ? width-captureWidth-gap : width
  const overlay = !landscape && overlayToolbar
  const available=Math.max(44,landscape ? height-toolbar-status-gap*2 : height-status-shutter-mode-(overlay?gap*3:toolbar+gap*4))
  const aspect=landscape ? (ratio==="16:9"?16/9:4/3) : (ratio==="16:9"?9/16:3/4)
  const viewWidth=Math.min(contentWidth,available*aspect),viewHeight=viewWidth/aspect
  // Use remaining safe-area height between the rows, anchoring the first and last rows.
  const used=viewHeight+status+(landscape?toolbar:shutter+mode+2*gap+(overlay?0:toolbar))
  const stackGap=Math.max(gap,(height-used)/(landscape || !overlay?2:1))
  return {width,height,landscape,compact,overlay,toolbar,status,shutter,mode,gap,stackGap,contentWidth,captureWidth,
    modeWidth:landscape?captureWidth:Math.min(width-48,280),toolbarGap:Math.max(4,(contentWidth-24-176)/3),
    viewWidth,viewHeight,railHeight:0,railWidth:0}
}
