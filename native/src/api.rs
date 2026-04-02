/// GPS 좌표 포인트
#[derive(Debug, Clone)]
pub struct GpsPoint {
    pub lat: f64,
    pub lng: f64,
}

/// 경로 유사도 체크 결과
#[derive(Debug)]
pub struct SimilarityResult {
    /// Jaccard 유사도 (0.0 ~ 1.0)
    pub score: f64,
    /// 70% 이상이면 true
    pub is_duplicate: bool,
}

/// 와인딩 필터 결과
#[derive(Debug)]
pub struct WindingScore {
    /// 와인딩 점수 (0.0 ~ 100.0)
    pub score: f64,
    /// 분류: "country" | "provincial" | "national"
    pub road_type: String,
}

// ── 경로 유사도 알고리즘 (Jaccard, ~1.1km 격자) ──────────────

const GRID_SIZE: f64 = 0.01; // ~1.1km 격자 셀
const INTERPOLATION_STEP: f64 = 0.005;

fn point_to_cell(lat: f64, lng: f64) -> (i64, i64) {
    ((lat / GRID_SIZE).floor() as i64, (lng / GRID_SIZE).floor() as i64)
}

fn route_to_cells(points: &[GpsPoint]) -> std::collections::HashSet<(i64, i64)> {
    let mut cells = std::collections::HashSet::new();
    for i in 0..points.len().saturating_sub(1) {
        let p1 = &points[i];
        let p2 = &points[i + 1];
        let dist = ((p2.lat - p1.lat).powi(2) + (p2.lng - p1.lng).powi(2)).sqrt();
        let steps = (dist / INTERPOLATION_STEP).ceil().max(1.0) as usize;
        for s in 0..=steps {
            let t = s as f64 / steps as f64;
            let lat = p1.lat + (p2.lat - p1.lat) * t;
            let lng = p1.lng + (p2.lng - p1.lng) * t;
            cells.insert(point_to_cell(lat, lng));
        }
    }
    cells
}

/// 두 경로의 유사도를 계산한다.
/// - `route_a`, `route_b`: GPS 포인트 벡터
/// - 반환: SimilarityResult { score, is_duplicate }
pub fn check_route_similarity(
    route_a: Vec<GpsPoint>,
    route_b: Vec<GpsPoint>,
) -> SimilarityResult {
    if route_a.is_empty() || route_b.is_empty() {
        return SimilarityResult { score: 0.0, is_duplicate: false };
    }
    let cells_a = route_to_cells(&route_a);
    let cells_b = route_to_cells(&route_b);

    let intersection = cells_a.intersection(&cells_b).count();
    let union = cells_a.union(&cells_b).count();

    let score = if union == 0 { 0.0 } else { intersection as f64 / union as f64 };
    SimilarityResult {
        score,
        is_duplicate: score >= 0.70,
    }
}

// ── 와인딩 필터 알고리즘 ──────────────────────────────────────

/// 두 점 사이 bearing(방위각) 변화(도)
fn bearing_change(p0: &GpsPoint, p1: &GpsPoint, p2: &GpsPoint) -> f64 {
    let b1 = bearing(p0, p1);
    let b2 = bearing(p1, p2);
    let mut delta = (b2 - b1).abs();
    if delta > 180.0 { delta = 360.0 - delta; }
    delta
}

fn bearing(a: &GpsPoint, b: &GpsPoint) -> f64 {
    let lat1 = a.lat.to_radians();
    let lat2 = b.lat.to_radians();
    let dlon = (b.lng - a.lng).to_radians();
    let x = dlon.sin() * lat2.cos();
    let y = lat1.cos() * lat2.sin() - lat1.sin() * lat2.cos() * dlon.cos();
    x.atan2(y).to_degrees()
}

/// 경로의 와인딩 점수를 계산한다.
///
/// 알고리즘:
/// 1. 연속 세 포인트 간 방위각 변화의 누적 합계를 경로 거리로 정규화
/// 2. 점수 0~100: 높을수록 꼬불꼬불한 도로 (시골길)
/// 3. road_type 분류: score < 20 → national, 20~50 → provincial, >50 → country
pub fn calc_winding_score(route: Vec<GpsPoint>) -> WindingScore {
    if route.len() < 3 {
        return WindingScore { score: 0.0, road_type: "national".to_string() };
    }

    let mut total_angle = 0.0_f64;
    let mut total_dist_m = 0.0_f64;

    for i in 1..route.len() - 1 {
        let angle = bearing_change(&route[i - 1], &route[i], &route[i + 1]);
        total_angle += angle;
        total_dist_m += haversine_m(&route[i - 1], &route[i]);
    }
    if total_dist_m < 1.0 {
        return WindingScore { score: 0.0, road_type: "national".to_string() };
    }

    // 각도/km 기준으로 정규화, 100도/km = 100점 기준 상한
    let score_raw = (total_angle / (total_dist_m / 1000.0)).min(200.0);
    let score = (score_raw / 200.0 * 100.0).clamp(0.0, 100.0);

    let road_type = if score < 20.0 {
        "national"
    } else if score < 50.0 {
        "provincial"
    } else {
        "country"
    };

    WindingScore { score, road_type: road_type.to_string() }
}

fn haversine_m(a: &GpsPoint, b: &GpsPoint) -> f64 {
    const R: f64 = 6_371_000.0;
    let d_lat = (b.lat - a.lat).to_radians();
    let d_lon = (b.lng - a.lng).to_radians();
    let sin_half_lat = (d_lat / 2.0).sin();
    let sin_half_lon = (d_lon / 2.0).sin();
    let h = sin_half_lat * sin_half_lat
        + a.lat.to_radians().cos()
        * b.lat.to_radians().cos()
        * sin_half_lon * sin_half_lon;
    2.0 * R * h.sqrt().asin()
}

// ── 단위 테스트 ───────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn identical_routes_are_100_pct_similar() {
        let route: Vec<GpsPoint> = (0..10)
            .map(|i| GpsPoint { lat: 37.0 + i as f64 * 0.01, lng: 127.0 })
            .collect();
        let result = check_route_similarity(route.clone(), route);
        assert!(result.score > 0.99);
        assert!(result.is_duplicate);
    }

    #[test]
    fn winding_score_straight_road_is_low() {
        // 완전 직선
        let route: Vec<GpsPoint> = (0..20)
            .map(|i| GpsPoint { lat: 37.0, lng: 127.0 + i as f64 * 0.01 })
            .collect();
        let ws = calc_winding_score(route);
        assert!(ws.score < 20.0, "직선 도로 점수가 너무 높음: {}", ws.score);
    }
}
