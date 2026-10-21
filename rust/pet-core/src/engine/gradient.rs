//! Memory-score → colour mapping.
//!
//! Colours are gamma-encoded sRGB in 0..=1 (what AppKit's `NSColor(srgbRed:...)` takes).
//! Interpolation and smoothing happen in OKLab so blends stay vivid: a straight sRGB blend
//! from green to red passes through a muddy brown, an OKLab blend passes through yellow.

/// Gamma-encoded sRGB colour, components in 0..=1.
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Rgb {
    pub r: f32,
    pub g: f32,
    pub b: f32,
}

impl Rgb {
    pub const fn new(r: f32, g: f32, b: f32) -> Self {
        Rgb { r, g, b }
    }

    pub const fn hex(v: u32) -> Self {
        Rgb {
            r: ((v >> 16) & 0xff) as f32 / 255.0,
            g: ((v >> 8) & 0xff) as f32 / 255.0,
            b: (v & 0xff) as f32 / 255.0,
        }
    }

    fn is_valid(&self) -> bool {
        [self.r, self.g, self.b]
            .iter()
            .all(|c| c.is_finite() && (0.0..=1.0).contains(c))
    }
}

/// A colour pinned at a score threshold (0..=100).
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Stop {
    pub threshold: f32,
    pub color: Rgb,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum GradientError {
    TooFewStops,
    TooManyStops,
    OutOfRange,
    NotAscending,
}

pub const MAX_STOPS: usize = 8;

pub const DEFAULT_GREEN: Rgb = Rgb::hex(0x34C759);
pub const DEFAULT_YELLOW: Rgb = Rgb::hex(0xFFD60A);
pub const DEFAULT_ORANGE: Rgb = Rgb::hex(0xFF9F0A);
pub const DEFAULT_RED: Rgb = Rgb::hex(0xFF453A);
pub const DEFAULT_COLORS: [Rgb; 4] = [DEFAULT_GREEN, DEFAULT_YELLOW, DEFAULT_ORANGE, DEFAULT_RED];
/// Upper bounds of the green, yellow and orange bands.
pub const DEFAULT_THRESHOLDS: [f32; 3] = [35.0, 60.0, 80.0];

/// Piecewise colour ramp over 0..=100. Stored inline so sampling never allocates.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Gradient {
    stops: [Stop; MAX_STOPS],
    len: usize,
}

impl Gradient {
    pub fn new(stops: &[Stop]) -> Result<Self, GradientError> {
        if stops.len() < 2 {
            return Err(GradientError::TooFewStops);
        }
        if stops.len() > MAX_STOPS {
            return Err(GradientError::TooManyStops);
        }
        for s in stops {
            if !s.threshold.is_finite()
                || !(0.0..=100.0).contains(&s.threshold)
                || !s.color.is_valid()
            {
                return Err(GradientError::OutOfRange);
            }
        }
        if stops.windows(2).any(|w| w[1].threshold < w[0].threshold) {
            return Err(GradientError::NotAscending);
        }
        let mut arr = [Stop::default(); MAX_STOPS];
        arr[..stops.len()].copy_from_slice(stops);
        Ok(Gradient {
            stops: arr,
            len: stops.len(),
        })
    }

    /// Builds the four-band ramp the settings UI exposes: each band is solid in its middle
    /// and blends into the next across a short window centred on the threshold, so a value
    /// sitting at a threshold never flips between two colours.
    pub fn from_bands(colors: [Rgb; 4], thresholds: [f32; 3]) -> Result<Self, GradientError> {
        let [t1, t2, t3] = thresholds;
        if !(t1.is_finite() && t2.is_finite() && t3.is_finite()) {
            return Err(GradientError::OutOfRange);
        }
        if !(0.0 < t1 && t1 < t2 && t2 < t3 && t3 < 100.0) {
            return Err(GradientError::NotAscending);
        }
        // Blend half-width: 5 points, shrunk when bands are narrow so stops stay ordered.
        let gaps = [t1, t2 - t1, t3 - t2, 100.0 - t3];
        let h = gaps.iter().fold(5.0f32, |h, g| h.min(g / 3.0));
        let [g, y, o, r] = colors;
        let stop = |threshold: f32, color| Stop { threshold, color };
        Self::new(&[
            stop(0.0, g),
            stop(t1 - h, g),
            stop(t1 + h, y),
            stop(t2 - h, y),
            stop(t2 + h, o),
            stop(t3 - h, o),
            stop(t3 + h, r),
            stop(100.0, r),
        ])
    }

    pub fn stops(&self) -> &[Stop] {
        &self.stops[..self.len]
    }

    /// Colour at `value` (clamped to 0..=100).
    pub fn sample(&self, value: f32) -> Rgb {
        let v = if value.is_finite() {
            value.clamp(0.0, 100.0)
        } else {
            0.0
        };
        let stops = self.stops();
        if v <= stops[0].threshold {
            return stops[0].color;
        }
        for w in stops.windows(2) {
            let (a, b) = (w[0], w[1]);
            if v <= b.threshold {
                if a.color == b.color {
                    return a.color; // solid band: exact, and skips the OKLab round trip
                }
                let span = b.threshold - a.threshold;
                if span <= f32::EPSILON {
                    return b.color;
                }
                let t = (v - a.threshold) / span;
                return Lab::from(a.color).lerp(Lab::from(b.color), t).into();
            }
        }
        stops[stops.len() - 1].color
    }
}

impl Default for Gradient {
    fn default() -> Self {
        Self::from_bands(DEFAULT_COLORS, DEFAULT_THRESHOLDS).expect("default gradient is valid")
    }
}

/// Exponentially approaches a target colour with time constant `tau` seconds.
/// Frame-rate independent: ten 0.1 s steps land where one 1 s step does.
#[derive(Clone, Copy, Debug)]
pub struct ColorSmoother {
    current: Option<Lab>,
    pub tau: f32,
}

impl ColorSmoother {
    pub const DEFAULT_TAU: f32 = 1.2;

    pub fn new(tau: f32) -> Self {
        ColorSmoother { current: None, tau }
    }

    /// Advances by `dt` seconds toward `target`. The first call snaps to the target so a
    /// freshly launched pet doesn't fade in from black.
    pub fn update(&mut self, target: Rgb, dt: f32) -> Rgb {
        let target = Lab::from(target);
        let next = match self.current {
            None => target,
            Some(cur) => {
                let k = if self.tau <= 0.0 {
                    1.0
                } else {
                    1.0 - (-dt.max(0.0) / self.tau).exp()
                };
                cur.lerp(target, k)
            }
        };
        self.current = Some(next);
        next.into()
    }

    pub fn value(&self) -> Option<Rgb> {
        self.current.map(Into::into)
    }
}

impl Default for ColorSmoother {
    fn default() -> Self {
        Self::new(Self::DEFAULT_TAU)
    }
}

// ---- OKLab (Björn Ottosson, 2020) -------------------------------------------------------

#[derive(Clone, Copy, Debug, PartialEq)]
struct Lab {
    l: f32,
    a: f32,
    b: f32,
}

impl Lab {
    fn lerp(self, o: Lab, t: f32) -> Lab {
        let t = t.clamp(0.0, 1.0);
        Lab {
            l: self.l + (o.l - self.l) * t,
            a: self.a + (o.a - self.a) * t,
            b: self.b + (o.b - self.b) * t,
        }
    }
}

fn to_linear(c: f32) -> f32 {
    if c <= 0.04045 {
        c / 12.92
    } else {
        ((c + 0.055) / 1.055).powf(2.4)
    }
}

fn to_gamma(c: f32) -> f32 {
    let c = c.clamp(0.0, 1.0);
    if c <= 0.003_130_8 {
        c * 12.92
    } else {
        1.055 * c.powf(1.0 / 2.4) - 0.055
    }
}

impl From<Rgb> for Lab {
    fn from(c: Rgb) -> Lab {
        let (r, g, b) = (to_linear(c.r), to_linear(c.g), to_linear(c.b));
        let l = (0.412_221_46 * r + 0.536_332_55 * g + 0.051_445_995 * b).cbrt();
        let m = (0.211_903_5 * r + 0.680_699_5 * g + 0.107_396_96 * b).cbrt();
        let s = (0.088_302_46 * r + 0.281_718_85 * g + 0.629_978_7 * b).cbrt();
        Lab {
            l: 0.210_454_26 * l + 0.793_617_8 * m - 0.004_072_047 * s,
            a: 1.977_998_5 * l - 2.428_592_2 * m + 0.450_593_7 * s,
            b: 0.025_904_037 * l + 0.782_771_77 * m - 0.808_675_77 * s,
        }
    }
}

impl From<Lab> for Rgb {
    fn from(c: Lab) -> Rgb {
        let l = c.l + 0.396_337_78 * c.a + 0.215_803_76 * c.b;
        let m = c.l - 0.105_561_346 * c.a - 0.063_854_17 * c.b;
        let s = c.l - 0.089_484_18 * c.a - 1.291_485_5 * c.b;
        let (l, m, s) = (l * l * l, m * m * m, s * s * s);
        Rgb {
            r: to_gamma(4.076_741_7 * l - 3.307_711_6 * m + 0.230_969_94 * s),
            g: to_gamma(-1.268_438 * l + 2.609_757_4 * m - 0.341_319_38 * s),
            b: to_gamma(-0.004_196_086_3 * l - 0.703_418_6 * m + 1.707_614_7 * s),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn close(a: Rgb, b: Rgb, eps: f32) -> bool {
        (a.r - b.r).abs() < eps && (a.g - b.g).abs() < eps && (a.b - b.b).abs() < eps
    }

    #[test]
    fn oklab_round_trip() {
        for c in [
            DEFAULT_GREEN,
            DEFAULT_RED,
            Rgb::new(0.0, 0.0, 0.0),
            Rgb::new(1.0, 1.0, 1.0),
        ] {
            let back: Rgb = Lab::from(c).into();
            assert!(close(c, back, 1e-3), "{c:?} -> {back:?}");
        }
    }

    #[test]
    fn exact_colours_at_stops() {
        let g = Gradient::new(&[
            Stop {
                threshold: 0.0,
                color: DEFAULT_GREEN,
            },
            Stop {
                threshold: 50.0,
                color: DEFAULT_YELLOW,
            },
            Stop {
                threshold: 100.0,
                color: DEFAULT_RED,
            },
        ])
        .unwrap();
        assert!(close(g.sample(0.0), DEFAULT_GREEN, 1e-3));
        assert!(close(g.sample(50.0), DEFAULT_YELLOW, 1e-3));
        assert!(close(g.sample(100.0), DEFAULT_RED, 1e-3));
    }

    #[test]
    fn default_bands_match_spec() {
        let g = Gradient::default();
        // Solid band centres.
        assert!(close(g.sample(10.0), DEFAULT_GREEN, 1e-3));
        assert!(close(g.sample(25.0), DEFAULT_GREEN, 1e-3));
        assert!(close(g.sample(48.0), DEFAULT_YELLOW, 1e-3));
        assert!(close(g.sample(70.0), DEFAULT_ORANGE, 1e-3));
        assert!(close(g.sample(95.0), DEFAULT_RED, 1e-3));
        // At a threshold the colour is the midpoint blend, not either neighbour.
        let mid = g.sample(35.0);
        assert!(!close(mid, DEFAULT_GREEN, 0.02) && !close(mid, DEFAULT_YELLOW, 0.02));
    }

    #[test]
    fn interpolation_is_continuous() {
        // No jumps anywhere along the ramp: neighbouring samples stay close.
        let g = Gradient::default();
        let mut prev = g.sample(0.0);
        for i in 1..=1000 {
            let c = g.sample(i as f32 / 10.0);
            assert!(close(prev, c, 0.03), "jump at {}", i as f32 / 10.0);
            prev = c;
        }
    }

    #[test]
    fn blend_moves_monotonically_toward_next_stop() {
        let g = Gradient::default();
        // Through the green→yellow window the red channel only rises.
        let mut last = g.sample(30.0).r;
        for i in 1..=10 {
            let r = g.sample(30.0 + i as f32).r;
            assert!(r >= last - 1e-5);
            last = r;
        }
    }

    #[test]
    fn values_outside_range_clamp() {
        let g = Gradient::default();
        assert_eq!(g.sample(-20.0), g.sample(0.0));
        assert_eq!(g.sample(250.0), g.sample(100.0));
        assert_eq!(g.sample(f32::NAN), g.sample(0.0));
    }

    #[test]
    fn invalid_stops_rejected() {
        let s = |t, c| Stop {
            threshold: t,
            color: c,
        };
        assert_eq!(
            Gradient::new(&[s(0.0, DEFAULT_RED)]),
            Err(GradientError::TooFewStops)
        );
        assert_eq!(
            Gradient::new(&[s(50.0, DEFAULT_RED), s(10.0, DEFAULT_RED)]),
            Err(GradientError::NotAscending)
        );
        assert_eq!(
            Gradient::new(&[s(0.0, DEFAULT_RED), s(120.0, DEFAULT_RED)]),
            Err(GradientError::OutOfRange)
        );
        assert_eq!(
            Gradient::new(&[s(0.0, Rgb::new(2.0, 0.0, 0.0)), s(100.0, DEFAULT_RED)]),
            Err(GradientError::OutOfRange)
        );
        assert_eq!(
            Gradient::new(&[s(0.0, DEFAULT_RED); 9]),
            Err(GradientError::TooManyStops)
        );
    }

    #[test]
    fn custom_thresholds_shift_bands() {
        let g = Gradient::from_bands(DEFAULT_COLORS, [20.0, 40.0, 60.0]).unwrap();
        assert!(close(g.sample(30.0), DEFAULT_YELLOW, 1e-3));
        assert!(close(g.sample(50.0), DEFAULT_ORANGE, 1e-3));
        assert!(close(g.sample(80.0), DEFAULT_RED, 1e-3));
    }

    #[test]
    fn narrow_bands_stay_ordered() {
        let g = Gradient::from_bands(DEFAULT_COLORS, [1.0, 2.0, 99.0]).unwrap();
        assert!(g
            .stops()
            .windows(2)
            .all(|w| w[0].threshold <= w[1].threshold));
        assert!(Gradient::from_bands(DEFAULT_COLORS, [50.0, 40.0, 60.0]).is_err());
        assert!(Gradient::from_bands(DEFAULT_COLORS, [0.0, 40.0, 60.0]).is_err());
    }

    #[test]
    fn smoother_snaps_first_then_eases() {
        let mut s = ColorSmoother::default();
        assert!(close(s.update(DEFAULT_GREEN, 0.016), DEFAULT_GREEN, 1e-4));
        let step = s.update(DEFAULT_RED, 0.1);
        assert!(!close(step, DEFAULT_GREEN, 1e-3) && !close(step, DEFAULT_RED, 0.05));
        for _ in 0..200 {
            s.update(DEFAULT_RED, 0.1);
        }
        assert!(close(s.value().unwrap(), DEFAULT_RED, 1e-3));
    }

    #[test]
    fn smoother_is_frame_rate_independent() {
        let mut fine = ColorSmoother::default();
        let mut coarse = ColorSmoother::default();
        fine.update(DEFAULT_GREEN, 0.0);
        coarse.update(DEFAULT_GREEN, 0.0);
        for _ in 0..10 {
            fine.update(DEFAULT_RED, 0.1);
        }
        coarse.update(DEFAULT_RED, 1.0);
        assert!(close(fine.value().unwrap(), coarse.value().unwrap(), 1e-3));
    }

    #[test]
    fn smoother_never_jumps() {
        // A sudden target change at 30 fps moves the colour only a small perceptual step
        // (OKLab distance; 0.02 is roughly a just-noticeable difference) per frame.
        let mut s = ColorSmoother::default();
        s.update(DEFAULT_GREEN, 0.0);
        let mut prev = Lab::from(DEFAULT_GREEN);
        for _ in 0..90 {
            let c = Lab::from(s.update(DEFAULT_RED, 1.0 / 30.0));
            let d =
                ((c.l - prev.l).powi(2) + (c.a - prev.a).powi(2) + (c.b - prev.b).powi(2)).sqrt();
            assert!(d < 0.02, "step {d}");
            prev = c;
        }
    }
}
