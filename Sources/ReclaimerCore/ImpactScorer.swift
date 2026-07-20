import Foundation

public struct ImpactScorer {
    public static func score(_ recommendation: ReclaimRecommendation) -> Double {
        Double(recommendation.reclaimableBytes) * recommendation.safetyScore / (1.0 - recommendation.effortScore * 0.5 + 0.5)
    }
}
