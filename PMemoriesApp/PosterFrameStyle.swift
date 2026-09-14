import SwiftUI

/// Katalog ramek na zdjęcia do plakatu "My Travel Journey" (11.09.2026,
/// user: "upiekszanie plakatu przez dodatki ktore Ci dalem rozne ramki i
/// inne ozdoby") — wycięte z arkusza "Photo Frames Collection 1/4"
/// (`PosterKit/frames/`), zamiast dotychczasowej pojedynczej, płaskiej
/// karty polaroidu (`Color.white` + cień) w `PolaroidView`.
///
/// Każdy styl to gotowy PNG z już wypalonym dekoracyjnym obramowaniem +
/// TOWARZYSZĄCA maska otworu (`maskAssetName`, biały = zdjęcie widoczne,
/// czarny = zasłonięte) — DOKŁADNY kształt otworu, nie przybliżenie
/// geometryczne. Pierwsza wersja próbowała `holeRect` (bounding box) +
/// prosty kształt (`Rectangle`/`RoundedRectangle`/`Circle`) — user złapał
/// realny bug na żywym urządzeniu: przy falistych/wielolistnych otworach
/// (chmurka, zdobiona etykieta) prostokąt/zaokrąglony prostokąt NIE
/// pokrywał się z prawdziwym kształtem otworu — "zdjecie wystaje za ramke
/// w innej sa przeswity bo jest nie dopasowane". Ten sam mechanizm co
/// `PremiumBadge*Mask` przy ramkach awatara — zdjęcie idzie POD ramką,
/// `.mask()` przycina je DOKŁADNIE do wyciętego kształtu otworu.
struct PosterFrameStyle {
    let assetName: String
    let maskAssetName: String
    /// Rozmiar canvasu assetu (px) — do wyliczenia proporcji przy skalowaniu.
    let canvasWidth: CGFloat
    let canvasHeight: CGFloat
    /// Bounding box otworu (ułamki 0...1 canvasu) — używany TYLKO do
    /// dobrania kadru/zoomu zdjęcia (żeby wypełniło hole, nie cały canvas
    /// ramki), nie do przycinania kształtu (to robi `maskAssetName`).
    let holeRect: (x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat)

    /// 11.09.2026, user: "to jest tragedia dlaczego ramki sa takie male
    /// zdjec prawie nie widac" — pierwsza runda renderowała każdą ramkę na
    /// tej samej małej szerokości bez względu na to, ile dekoracji zjadała
    /// otwór. `PosterFrameRound` (koło + duży kiść liści zachodzący NA
    /// otwór) i `PosterFrameHeart` (ręcznie zmierzony `holeRect`, za mały,
    /// bez wygenerowanej maski — kreskowana obwódka łączyła wnętrze z
    /// zewnętrzem przy automatycznym wykrywaniu) świadomie WYCIĘTE z tej
    /// listy. Zostają tylko style z dużym, dobrze zmierzonym otworem I
    /// prawdziwą maską kształtu.
    static let all: [PosterFrameStyle] = [
        PosterFrameStyle(assetName: "PosterFrameTorn", maskAssetName: "PosterFrameTornMask",
                         canvasWidth: 432, canvasHeight: 266,
                         holeRect: (0.2546, 0.2068, 0.6782, 0.6842)),
        PosterFrameStyle(assetName: "PosterFrameFilmstrip", maskAssetName: "PosterFrameFilmstripMask",
                         canvasWidth: 360, canvasHeight: 238,
                         holeRect: (0.125, 0.1807, 0.7528, 0.6471)),
        PosterFrameStyle(assetName: "PosterFrameGoldOrnate", maskAssetName: "PosterFrameGoldOrnateMask",
                         canvasWidth: 308, canvasHeight: 206,
                         holeRect: (0.0617, 0.1019, 0.8766, 0.7961)),
        PosterFrameStyle(assetName: "PosterFrameStamp", maskAssetName: "PosterFrameStampMask",
                         canvasWidth: 322, canvasHeight: 248,
                         holeRect: (0.1646, 0.1169, 0.7516, 0.7581)),
        PosterFrameStyle(assetName: "PosterFrameScallop", maskAssetName: "PosterFrameScallopMask",
                         canvasWidth: 223, canvasHeight: 213,
                         holeRect: (0.1256, 0.0704, 0.7489, 0.7887)),
        PosterFrameStyle(assetName: "PosterFrameAirmail", maskAssetName: "PosterFrameAirmailMask",
                         canvasWidth: 366, canvasHeight: 240,
                         holeRect: (0.082, 0.1292, 0.8361, 0.7417)),
        PosterFrameStyle(assetName: "PosterFrameLabel", maskAssetName: "PosterFrameLabelMask",
                         canvasWidth: 293, canvasHeight: 209,
                         holeRect: (0.0887, 0.1292, 0.8191, 0.756)),
        PosterFrameStyle(assetName: "PosterFrameCloud", maskAssetName: "PosterFrameCloudMask",
                         canvasWidth: 353, canvasHeight: 215,
                         holeRect: (0.068, 0.107, 0.8555, 0.8512)),
        PosterFrameStyle(assetName: "PosterFrameNotebook", maskAssetName: "PosterFrameNotebookMask",
                         canvasWidth: 313, canvasHeight: 216,
                         holeRect: (0.1629, 0.1481, 0.7284, 0.75)),
        PosterFrameStyle(assetName: "PosterFrameTriangle", maskAssetName: "PosterFrameTriangleMask",
                         canvasWidth: 327, canvasHeight: 283,
                         holeRect: (0.0887, 0.1661, 0.7248, 0.6784)),
        PosterFrameStyle(assetName: "PosterFramePolaroid", maskAssetName: "PosterFramePolaroidMask",
                         canvasWidth: 270, canvasHeight: 301,
                         holeRect: (0.1222, 0.1395, 0.7556, 0.6611)),
    ]

    static func style(forIndex index: Int) -> PosterFrameStyle {
        all[index % all.count]
    }
}

extension View {
    /// Renderuje `self` (zdjęcie, `.resizable().aspectRatio(.fill)` bez
    /// `.frame()`) wewnątrz `style.holeRect` (dla dobrego kadru/zoomu),
    /// przycięte DOKŁADNYM kształtem otworu (`style.maskAssetName`), z
    /// samą ramką (`style.assetName`) na wierzchu — ten sam układ co
    /// `avatarFramedPhoto` przy ramkach awatara.
    @ViewBuilder
    func posterFramed(_ style: PosterFrameStyle, width: CGFloat) -> some View {
        let height = width * style.canvasHeight / style.canvasWidth
        let holeW = width * style.holeRect.width
        let holeH = height * style.holeRect.height
        let holeX = width * (style.holeRect.x + style.holeRect.width / 2)
        let holeY = height * (style.holeRect.y + style.holeRect.height / 2)
        ZStack {
            self
                .frame(width: holeW, height: holeH)
                .position(x: holeX, y: holeY)
        }
        .frame(width: width, height: height)
        .mask(
            Image(style.maskAssetName)
                .resizable()
                .frame(width: width, height: height)
        )
        .overlay(
            Image(style.assetName)
                .resizable()
                .frame(width: width, height: height)
        )
        .frame(width: width, height: height)
    }
}
