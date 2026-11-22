#!/usr/bin/env python3
import os
import wave

import numpy as np


RATE = 24000
OUTPUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "audio")


def envelope(length, attack=0.02, release=0.15):
    t = np.arange(length) / RATE
    duration = length / RATE
    return np.minimum(1.0, t / max(attack, 1.0 / RATE)) * np.minimum(
        1.0, np.maximum(0.0, (duration - t) / max(release, 1.0 / RATE))
    )


def noise(rng, length):
    return rng.normal(0.0, 1.0, length)


def build(name, duration, seed):
    rng = np.random.default_rng(seed)
    length = int(RATE * duration)
    t = np.arange(length) / RATE
    env = envelope(length, 0.08, min(0.35, duration * 0.18))
    hiss = noise(rng, length)
    if name == "miner_drill_rumble":
        signal = 0.48 * np.sin(2 * np.pi * 47 * t) + 0.22 * np.sin(2 * np.pi * 71 * t)
        signal += 0.24 * hiss * (0.65 + 0.35 * np.sin(2 * np.pi * 9 * t))
    elif name == "smelter_roar":
        signal = 0.55 * hiss + 0.22 * np.sin(2 * np.pi * 94 * t) + 0.12 * np.sin(2 * np.pi * 141 * t)
    elif name == "constructor_press":
        pulse = np.maximum(0.0, np.sin(2 * np.pi * 1.15 * t)) ** 10
        signal = 0.5 * np.sin(2 * np.pi * 62 * t) + 0.28 * hiss
        signal *= 0.25 + 0.75 * pulse
    elif name == "assembler_servo":
        phase = 2 * np.pi * (220 * t + 90 * t * t / duration)
        signal = 0.48 * np.sin(phase) + 0.14 * np.sin(2 * phase) + 0.08 * hiss
    elif name == "geo_tap_steam":
        signal = 0.72 * hiss * (0.7 + 0.3 * np.sin(2 * np.pi * 0.8 * t))
        signal += 0.12 * np.sin(2 * np.pi * 380 * t)
    elif name == "belt_rattle":
        pulse = np.maximum(0.0, np.sin(2 * np.pi * 4.5 * t)) ** 6
        signal = pulse * (0.42 * hiss + 0.32 * np.sin(2 * np.pi * 170 * t))
    elif name == "placement_confirm":
        signal = np.sin(2 * np.pi * 660 * t) + 0.45 * np.sin(2 * np.pi * 990 * t)
        env = envelope(length, 0.005, duration * 0.8)
    elif name == "invalid_placement":
        signal = 0.5 * np.sin(2 * np.pi * 160 * t) + 0.32 * np.sin(2 * np.pi * 120 * t)
        env = envelope(length, 0.004, duration * 0.8)
    elif name == "dismantle":
        signal = 0.5 * np.sin(2 * np.pi * (210 - 100 * t / duration) * t) + 0.25 * hiss
        env = envelope(length, 0.01, duration * 0.75)
    elif name == "pick_hit":
        signal = 0.65 * np.sin(2 * np.pi * 82 * t) + 0.4 * hiss
        env = np.exp(-t * 15.0)
    else:
        signal = 0.56 * np.sin(2 * np.pi * 1450 * t) + 0.2 * hiss
        env = np.exp(-t * 30.0)
    signal = signal * env
    signal *= 0.82 / max(0.82, float(np.max(np.abs(signal))))
    return np.asarray(np.clip(signal, -1.0, 1.0) * 32767, dtype="<i2")


def main():
    os.makedirs(OUTPUT, exist_ok=True)
    effects = [
        ("miner_drill_rumble", 3.0),
        ("smelter_roar", 3.0),
        ("constructor_press", 2.4),
        ("assembler_servo", 2.6),
        ("geo_tap_steam", 2.5),
        ("belt_rattle", 2.0),
        ("placement_confirm", 0.42),
        ("invalid_placement", 0.38),
        ("dismantle", 0.5),
        ("pick_hit", 0.28),
        ("ui_click", 0.12),
    ]
    for seed, (name, duration) in enumerate(effects, 1):
        samples = build(name, duration, seed)
        path = os.path.join(OUTPUT, name + ".wav")
        with wave.open(path, "wb") as output:
            output.setnchannels(1)
            output.setsampwidth(2)
            output.setframerate(RATE)
            output.writeframes(samples.tobytes())
        peak = float(np.max(np.abs(samples.astype(np.float32))) / 32767.0)
        print(f"{name}: peak {20 * np.log10(peak):.2f} dBFS, clipped={peak >= 1.0}")


if __name__ == "__main__":
    main()
