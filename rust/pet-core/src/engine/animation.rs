//! Frame stepping and CPU-driven speed.

/// Which animation a pet shows. Discriminants index `ActorConfig::animations` and match
/// the C `PET_STATE_*` constants.
#[repr(u8)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PetState {
    Idle = 0,
    Walk = 1,
    Run = 2,
    Jump = 3,
    Sleep = 4,
}

pub const STATE_COUNT: usize = 5;

impl PetState {
    pub fn from_raw(v: u8) -> Option<Self> {
        match v {
            0 => Some(Self::Idle),
            1 => Some(Self::Walk),
            2 => Some(Self::Run),
            3 => Some(Self::Jump),
            4 => Some(Self::Sleep),
            _ => None,
        }
    }

    pub fn index(self) -> usize {
        self as usize
    }
}

/// Frame count, base rate and looping for one animation. Mirrors C `PetAnimSpec`.
#[repr(C)]
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct AnimSpec {
    pub frames: u32,
    pub fps: f32,
    pub looping: u8,
}

impl AnimSpec {
    pub const fn new(frames: u32, fps: f32, looping: bool) -> Self {
        AnimSpec {
            frames,
            fps,
            looping: looping as u8,
        }
    }

    pub fn is_valid(&self) -> bool {
        self.frames > 0
            && self.frames <= 64
            && self.fps.is_finite()
            && self.fps > 0.0
            && self.fps <= 60.0
    }
}

impl Default for AnimSpec {
    fn default() -> Self {
        AnimSpec::new(1, 1.0, true)
    }
}

pub const SPEED_MIN: f32 = 0.25;
pub const SPEED_MAX: f32 = 4.0;

const SLOW: f32 = 0.6;
const NORMAL: f32 = 1.0;
const FAST: f32 = 1.8;
const LOW_EDGE: f32 = 25.0;
const HIGH_EDGE: f32 = 65.0;
const BLEND: f32 = 5.0;

fn smoothstep(edge0: f32, edge1: f32, x: f32) -> f32 {
    let t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
    t * t * (3.0 - 2.0 * t)
}

/// Speed multiplier for a (smoothed) CPU percentage: slow below 25%, normal 25–65%,
/// fast above 65%, blended over ±5 points around each edge so speed never snaps.
pub fn cpu_speed(cpu: f32) -> f32 {
    let cpu = if cpu.is_finite() {
        cpu.clamp(0.0, 100.0)
    } else {
        0.0
    };
    let up = smoothstep(LOW_EDGE - BLEND, LOW_EDGE + BLEND, cpu);
    let up2 = smoothstep(HIGH_EDGE - BLEND, HIGH_EDGE + BLEND, cpu);
    SLOW + (NORMAL - SLOW) * up + (FAST - NORMAL) * up2
}

/// Exponential moving average used to calm CPU readings before they drive speed.
#[derive(Clone, Copy, Debug, Default)]
pub struct Ema {
    value: Option<f32>,
}

impl Ema {
    pub const ALPHA: f32 = 0.4;

    pub fn push(&mut self, x: f32) -> f32 {
        let v = match self.value {
            None => x,
            Some(v) => v + Self::ALPHA * (x - v),
        };
        self.value = Some(v);
        v
    }

    pub fn get(&self) -> f32 {
        self.value.unwrap_or(0.0)
    }
}

/// How early (in frames) a frame may be shown. Ticks that arrive up to `1 − this` of a frame
/// late still advance exactly once, so it must stay well above the host timer's tolerance.
const FRAME_DUE_TOLERANCE: f32 = 0.3;

/// Steps through one animation's frames in real time.
#[derive(Clone, Copy, Debug, Default)]
pub struct Animator {
    frame: u32,
    accumulator: f32,
    finished: bool,
}

impl Animator {
    pub fn reset(&mut self) {
        *self = Animator::default();
    }

    pub fn frame(&self) -> u32 {
        self.frame
    }

    /// True once a non-looping animation has shown its last frame for a full frame time.
    pub fn finished(&self) -> bool {
        self.finished
    }

    /// Advances by `dt * speed` seconds. Returns true when the visible frame changed.
    pub fn advance(&mut self, spec: &AnimSpec, dt: f32, speed: f32) -> bool {
        if self.finished || spec.frames == 0 {
            return false;
        }
        // accumulator is in units of frames.
        self.accumulator += dt.max(0.0) * spec.fps * speed.clamp(SPEED_MIN, SPEED_MAX);
        let mut changed = false;
        // Show a frame once it is *nearly* due. The host ticks once per frame with a timer
        // that jitters by ±10 %; with a strict `>= 1.0` a slightly early tick would show
        // nothing and the next one would jump two frames, which reads as a stutter. The
        // remainder may go slightly negative, so the long-run rate stays exact.
        while self.accumulator >= 1.0 - FRAME_DUE_TOLERANCE {
            self.accumulator -= 1.0;
            if self.frame + 1 < spec.frames {
                self.frame += 1;
                changed = true;
            } else if spec.looping != 0 {
                self.frame = 0;
                changed = true;
            } else {
                self.finished = true;
                self.accumulator = 0.0;
                break;
            }
        }
        changed
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn speed_bands() {
        assert!((cpu_speed(0.0) - SLOW).abs() < 1e-6);
        assert!((cpu_speed(10.0) - SLOW).abs() < 1e-6);
        assert!((cpu_speed(45.0) - NORMAL).abs() < 1e-6);
        assert!((cpu_speed(90.0) - FAST).abs() < 1e-6);
        assert!((cpu_speed(100.0) - FAST).abs() < 1e-6);
    }

    #[test]
    fn speed_is_monotonic_and_continuous() {
        let mut prev = cpu_speed(0.0);
        for i in 1..=1000 {
            let s = cpu_speed(i as f32 / 10.0);
            assert!(s >= prev - 1e-6);
            assert!(s - prev < 0.02, "snap at {}", i as f32 / 10.0);
            prev = s;
        }
    }

    #[test]
    fn speed_handles_garbage() {
        assert_eq!(cpu_speed(f32::NAN), SLOW);
        assert_eq!(cpu_speed(-5.0), SLOW);
    }

    #[test]
    fn ema_smooths() {
        let mut e = Ema::default();
        assert_eq!(e.push(0.0), 0.0);
        let v = e.push(100.0);
        assert!((v - 40.0).abs() < 1e-4);
    }

    #[test]
    fn looping_wraps() {
        let spec = AnimSpec::new(4, 10.0, true);
        let mut a = Animator::default();
        for _ in 0..4 {
            a.advance(&spec, 0.1, 1.0);
        }
        assert_eq!(a.frame(), 0);
        a.advance(&spec, 0.25, 1.0);
        assert_eq!(a.frame(), 2);
        assert!(!a.finished());
    }

    #[test]
    fn speed_scales_frame_rate() {
        let spec = AnimSpec::new(8, 10.0, true);
        let mut slow = Animator::default();
        let mut fast = Animator::default();
        slow.advance(&spec, 0.3, 1.0);
        fast.advance(&spec, 0.3, 2.0);
        assert_eq!(slow.frame(), 3);
        assert_eq!(fast.frame(), 6);
    }

    #[test]
    fn one_shot_finishes_and_holds_last_frame() {
        let spec = AnimSpec::new(3, 10.0, false);
        let mut a = Animator::default();
        a.advance(&spec, 0.25, 1.0);
        assert_eq!(a.frame(), 2);
        assert!(!a.finished());
        a.advance(&spec, 0.1, 1.0);
        assert!(a.finished());
        assert_eq!(a.frame(), 2);
        assert!(!a.advance(&spec, 1.0, 1.0));
    }

    #[test]
    fn jittery_ticks_never_skip_or_double() {
        // Model the host's repeating Timer: it fires on a fixed grid (n × interval) and may
        // be late by its tolerance (20 %) on any tick; test with 30 % for margin. Every tick
        // must show exactly one new frame: no stutter from a skipped or doubled frame.
        let spec = AnimSpec::new(6, 12.0, true);
        let interval = 1.0 / 12.0;
        let mut a = Animator::default();
        let mut seed = 0x2545_F491_u32;
        let mut last_fire = 0.0f64;
        for n in 1..=2000u32 {
            seed = seed.wrapping_mul(1_664_525).wrapping_add(1_013_904_223);
            let late = (seed >> 8) as f64 / (1u32 << 24) as f64 * 0.30 * interval;
            let fire = n as f64 * interval + late;
            let dt = (fire - last_fire) as f32;
            last_fire = fire;
            let before = a.frame();
            assert!(a.advance(&spec, dt, 1.0), "tick {n} showed no new frame");
            assert_eq!(a.frame(), (before + 1) % 6, "tick {n} skipped a frame");
        }
    }

    #[test]
    fn strict_threshold_would_stutter() {
        // Documents why the tolerance exists: a tick 5 % early shows nothing without it.
        let spec = AnimSpec::new(6, 12.0, true);
        let mut a = Animator::default();
        assert!(a.advance(&spec, 0.95 / 12.0, 1.0));
    }

    #[test]
    fn state_round_trips() {
        for i in 0..STATE_COUNT as u8 {
            assert_eq!(PetState::from_raw(i).unwrap() as u8, i);
        }
        assert_eq!(PetState::from_raw(5), None);
    }
}
