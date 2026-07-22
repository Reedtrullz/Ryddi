import Foundation

public struct ImpactScorer {
    public static func score(_ recommendation: ReclaimRecommendation) -> Double {
        let denominator = 1.5 - recommendation.effortScore * 0.5
        return Double(recommendation.reclaimableBytes) * recommendation.safetyScore / denominator
    }
}
