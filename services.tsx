import { Canvas, Image, ImageRenderer, Path, ZStack } from "scripting"
import { CaptureRecord, Fix, Settings, outputSize, cropSize, orientedSize, within } from "./core"
import { drawStamp } from "./stamp"
export const folder = Path.join(FileManager.documentsDirectory, "Momentra")
let geoAt = 0
let geoCache: { key: string; address: string } | null = null
export async function enrich(fix: Fix | null, settings: Settings): Promise<{address: string; map: UIImage | null; warnings: string[]}> {
  const warnings: string[] = []; let address = "", map: UIImage | null = null
  if (!fix || !settings.gps) return {address,map,warnings}
  const key = fix.latitude.toFixed(4)+","+fix.longitude.toFixed(4)
  if (geoCache?.key === key) address = geoCache.address
  else if (Date.now() - geoAt >= 60000) {
    geoAt = Date.now()
    try {
      const places = await within(Location.reverseGeocode({latitude:fix.latitude,longitude:fix.longitude,locale:"pt-BR"}),4000,null)
      const p = places?.[0]
      address = p ? [[p.thoroughfare,p.subThoroughfare].filter(Boolean).join(" "),p.subLocality,p.locality,p.administrativeArea].filter(Boolean).join(" · ") : ""
      if (address) geoCache = {key,address}
    } catch (_) { /* Coordinates remain valid without geocoding. */ }
    if (!address) warnings.push("Endereço indisponível; coordenadas preservadas")
  }
  if (settings.map) {
    try {
      if (typeof MapSnapshotter === "undefined") throw new Error("MapSnapshotter indisponível")
      const snap = await within(MapSnapshotter.take({
        region:{center:{latitude:fix.latitude,longitude:fix.longitude},span:{latitudeDelta:0.003,longitudeDelta:0.003}},
        size:{width:280,height:280},scale:1,mapStyle:{style:"imagery"},
        annotations:[{coordinate:{latitude:fix.latitude,longitude:fix.longitude},tintColor:"systemRed"}],
      }),6000,null)
      map = snap?.image ?? null
    } catch (_) { /* Photograph is never blocked by map availability. */ }
    if (!map) warnings.push("Mapa indisponível; foto preservada sem mapa")
  }
  return {address,map,warnings}
}
export async function renderStamped(image: UIImage, record: CaptureRecord, settings: Settings, map: UIImage | null): Promise<string> {
  // Encoded dimensions + EXIF orientation determine the displayed aspect ratio.
  let dimensions = {width:image.width,height:image.height}
  if (typeof ImageIO !== "undefined") {
    const metadata = await ImageIO.readMetadata(record.original)
    if (metadata.pixelWidth && metadata.pixelHeight) dimensions = orientedSize(metadata.pixelWidth,metadata.pixelHeight,metadata.orientation)
  } else if (["left","right","leftMirrored","rightMirrored"].includes(image.imageOrientation)) {
    dimensions = {width:image.height,height:image.width}
  }
  const crop = cropSize(dimensions.width,dimensions.height,settings.aspectRatio)
  const size = outputSize(crop.width,crop.height)
  const logoPath = settings.profiles[record.profile].logoPath
  let logo: UIImage | null = null
  if (logoPath) { logo = UIImage.fromFile(logoPath); if (!logo) record.warnings.push("Logotipo indisponível") }
  // UIImage is displayed by Image so UIKit applies its EXIF orientation before rendering.
  const data = await ImageRenderer.toJPEGData(
    <ZStack frame={size} clipped>
      <Image image={image} resizable scaleToFill frame={size} clipped />
      {settings.stamp ? <Canvas opaque={false} frame={size} draw={(ctx) => drawStamp(ctx,size.width,size.height,settings,record,map ? {image:map} : null,logo ? {image:logo} : null)} /> : null}
    </ZStack>,{scale:1,opaque:true,compressionQuality:0.94})
  const path = Path.join(folder,record.id+".jpg")
  await FileManager.writeAsData(path,data)
  return path
}
export async function persistRecord(record: CaptureRecord) {
  await FileManager.writeAsString(Path.join(folder,record.id+".json"),JSON.stringify(record,null,2))
}
