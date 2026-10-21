//! Turns metrics into what a pet looks like on each frame: its colour (from memory), its
//! pace (from CPU) and which animation frame to show.

pub mod animation;
pub mod gradient;

use crate::monitoring::Metrics;
use animation::{cpu_speed, AnimSpec, Animator, Ema, PetState, SPEED_MAX, SPEED_MIN, STATE_COUNT};
use gradient::{ColorSmoother, Gradient, Rgb};

/// Which memory figure drives the colour. Mirrors C `PetMemoryMode`.
#[repr(u8)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum MemoryMode {
    Usage = 0,
    Pressure = 1,
}

impl MemoryMode {
    pub fn from_raw(v: u8) -> Option<Self> {
        match v {
            0 => Some(Self::Usage),
            1 => Some(Self::Pressure),
            _ => None,
        }
    }
}

/// Per-pet configuration. Mirrors C `PetActorConfig`.
#[repr(C)]
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct ActorConfig {
    pub memory_mode: u8,
    pub cpu_driven_speed: u8,
    /// The `PetState` whose animation is shown (the menu bar uses Run).
    pub state: u8,
    pub reserved: u8,
    /// Used when `cpu_driven_speed == 0`; clamped to `SPEED_MIN..=SPEED_MAX`.
    pub manual_speed: f32,
    pub animations: [AnimSpec; STATE_COUNT],
}

impl Default for ActorConfig {
    fn default() -> Self {
        ActorConfig {
            memory_mode: MemoryMode::Usage as u8,
            cpu_driven_speed: 1,
            state: PetState::Run as u8,
            reserved: 0,
            manual_speed: 1.0,
            animations: [
                AnimSpec::new(4, 4.0, true),
                AnimSpec::new(6, 8.0, true),
                AnimSpec::new(6, 12.0, true),
                AnimSpec::new(6, 10.0, false),
                AnimSpec::new(4, 2.0, true),
            ],
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ConfigError;

impl ActorConfig {
    fn validate(&self) -> Result<(MemoryMode, PetState), ConfigError> {
        let memory = MemoryMode::from_raw(self.memory_mode).ok_or(ConfigError)?;
        let state = PetState::from_raw(self.state).ok_or(ConfigError)?;
        let speed_ok = self.manual_speed.is_finite() && self.manual_speed > 0.0;
        if !speed_ok || !self.animations.iter().all(AnimSpec::is_valid) {
            return Err(ConfigError);
        }
        Ok((memory, state))
    }
}

/// Everything the renderer needs for one frame. Mirrors C `PetFrame`.
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Frame {
    pub speed_multiplier: f32,
    pub memory_score: f32,
    pub tint: Rgb,
    pub frame_index: u32,
    pub state: u8,
    pub reserved: [u8; 3],
}

/// One pet: animation, speed and colour, driven by shared metrics.
pub struct Actor {
    config: ActorConfig,
    memory_mode: MemoryMode,
    state: PetState,
    gradient: Gradient,
    smoother: ColorSmoother,
    animator: Animator,
    cpu: Ema,
    metrics: Metrics,
}

impl Actor {
    pub fn new() -> Self {
        let config = ActorConfig::default();
        let (memory_mode, state) = config.validate().expect("default config is valid");
        Actor {
            config,
            memory_mode,
            state,
            gradient: Gradient::default(),
            smoother: ColorSmoother::default(),
            animator: Animator::default(),
            cpu: Ema::default(),
            metrics: Metrics::default(),
        }
    }

    pub fn config(&self) -> &ActorConfig {
        &self.config
    }

    /// Applies a configuration; an invalid one is rejected and the old one kept.
    pub fn configure(&mut self, config: ActorConfig) -> Result<(), ConfigError> {
        let (memory_mode, state) = config.validate()?;
        if config.animations != self.config.animations || state != self.state {
            self.animator.reset();
        }
        self.config = config;
        self.memory_mode = memory_mode;
        self.state = state;
        Ok(())
    }

    pub fn set_gradient(&mut self, gradient: Gradient) {
        self.gradient = gradient;
    }

    pub fn update_metrics(&mut self, metrics: &Metrics) {
        self.cpu.push(metrics.cpu_percent);
        self.metrics = *metrics;
    }

    pub fn memory_score(&self) -> f32 {
        match self.memory_mode {
            MemoryMode::Usage => self.metrics.ram_used_percent,
            MemoryMode::Pressure => self.metrics.pressure_score,
        }
    }

    pub fn speed(&self) -> f32 {
        let s = if self.config.cpu_driven_speed != 0 {
            cpu_speed(self.cpu.get())
        } else {
            self.config.manual_speed
        };
        s.clamp(SPEED_MIN, SPEED_MAX)
    }

    /// Advances by `dt` seconds (clamped to 0.25 s, so waking from sleep doesn't race
    /// through frames). Never allocates.
    pub fn tick(&mut self, dt: f32) -> Frame {
        let dt = if dt.is_finite() {
            dt.clamp(0.0, 0.25)
        } else {
            0.0
        };
        let speed = self.speed();
        let spec = self.config.animations[self.state.index()];
        self.animator.advance(&spec, dt, speed);
        let score = self.memory_score();
        Frame {
            speed_multiplier: speed,
            memory_score: score,
            tint: self.smoother.update(self.gradient.sample(score), dt),
            frame_index: self.animator.frame(),
            state: self.state as u8,
            reserved: [0; 3],
        }
    }
}

impl Default for Actor {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn metrics(cpu: f32, ram: f32, pressure: f32) -> Metrics {
        Metrics {
            cpu_percent: cpu,
            ram_used_percent: ram,
            pressure_score: pressure,
            kernel_pressure_level: 1,
            ..Default::default()
        }
    }

    #[test]
    fn shows_configured_animation() {
        let mut a = Actor::new();
        assert_eq!(a.tick(0.1).state, PetState::Run as u8);
        a.configure(ActorConfig {
            state: PetState::Sleep as u8,
            ..*a.config()
        })
        .unwrap();
        assert_eq!(a.tick(0.1).state, PetState::Sleep as u8);
    }

    #[test]
    fn frames_advance_and_loop() {
        let mut a = Actor::new();
        a.configure(ActorConfig {
            cpu_driven_speed: 0,
            ..*a.config()
        })
        .unwrap();
        let seen: Vec<u32> = (0..12).map(|_| a.tick(1.0 / 12.0).frame_index).collect();
        assert_eq!(seen, vec![1, 2, 3, 4, 5, 0, 1, 2, 3, 4, 5, 0]); // run: 6 frames @ 12 fps
    }

    #[test]
    fn colour_follows_selected_memory_mode() {
        let mut a = Actor::new();
        a.update_metrics(&metrics(10.0, 90.0, 10.0));
        let usage = a.tick(0.1);
        assert!(usage.tint.r > 0.9 && usage.tint.g < 0.5, "{:?}", usage.tint); // red
        a.configure(ActorConfig {
            memory_mode: MemoryMode::Pressure as u8,
            ..*a.config()
        })
        .unwrap();
        for _ in 0..100 {
            a.tick(0.1);
        }
        let pressure = a.tick(0.1);
        assert_eq!(pressure.memory_score, 10.0);
        assert!(pressure.tint.g > pressure.tint.r); // green
    }

    #[test]
    fn colour_changes_smoothly() {
        let mut a = Actor::new();
        a.update_metrics(&metrics(0.0, 10.0, 0.0));
        let start = a.tick(0.033).tint;
        a.update_metrics(&metrics(0.0, 95.0, 0.0));
        let next = a.tick(0.033).tint;
        assert!((next.r - start.r).abs() < 0.1 && (next.g - start.g).abs() < 0.1);
    }

    #[test]
    fn cpu_drives_speed_unless_manual() {
        let mut a = Actor::new();
        for _ in 0..20 {
            a.update_metrics(&metrics(95.0, 0.0, 0.0));
        }
        assert!(a.tick(0.1).speed_multiplier > 1.5);
        for _ in 0..20 {
            a.update_metrics(&metrics(2.0, 0.0, 0.0));
        }
        assert!(a.tick(0.1).speed_multiplier < 0.7);
        a.configure(ActorConfig {
            cpu_driven_speed: 0,
            manual_speed: 2.5,
            ..*a.config()
        })
        .unwrap();
        assert_eq!(a.tick(0.1).speed_multiplier, 2.5);
    }

    #[test]
    fn invalid_config_rejected_and_ignored() {
        let mut a = Actor::new();
        let good = *a.config();
        for bad in [
            ActorConfig {
                memory_mode: 9,
                ..good
            },
            ActorConfig { state: 7, ..good },
            ActorConfig {
                manual_speed: f32::NAN,
                ..good
            },
            ActorConfig {
                manual_speed: 0.0,
                ..good
            },
            ActorConfig {
                animations: [AnimSpec::new(0, 1.0, true); STATE_COUNT],
                ..good
            },
        ] {
            assert_eq!(a.configure(bad), Err(ConfigError));
        }
        assert_eq!(*a.config(), good);
    }

    #[test]
    fn huge_or_bad_dt_is_safe() {
        let mut a = Actor::new();
        let f = a.tick(1e9);
        assert!(f.frame_index < 6 && f.tint.r.is_finite());
        let g = a.tick(f32::NAN);
        assert!(g.tint.g.is_finite());
    }
}
