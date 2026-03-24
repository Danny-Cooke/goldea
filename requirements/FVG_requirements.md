# Fair Value Gap (FVG) Module — Requirements

## Overview

A modular Fair Value Gap detector for XAUUSD across 7 timeframes: M1, M5, M15, M30, H1, H4, D1.

The EA can be attached as an indicator to visually verify FVG detection. When attached to a chart, only the FVGs belonging to that chart's timeframe are drawn. All other timeframes are monitored internally for future bias/trading logic.

---

## FVG Definition

A standard 3-candle Fair Value Gap:
- **Bullish FVG**: Candle 3 low is higher than Candle 1 high (gap between them)
- **Bearish FVG**: Candle 3 high is lower than Candle 1 low (gap between them)

---

## Inputs

### Display
| Input | Description | Default |
|-------|-------------|---------|
| FVG - Display - Bullish Colour | Rectangle colour for bullish FVGs | Green |
| FVG - Display - Bearish Colour | Rectangle colour for bearish FVGs | Red |
| FVG - Display - Rectangle Opacity | Fill opacity of the rectangles | 50% |

### History
| Input | Description | Default |
|-------|-------------|---------|
| FVG - History - Candles Back | How many candles back to scan for FVGs | 50 |

### Filter
| Input | Description | Default |
|-------|-------------|---------|
| FVG - Filter - Minimum Size (pips) | Minimum gap size in pips for a valid FVG | 5 |

### Range Detection
| Input | Description | Default |
|-------|-------------|---------|
| FVG - Range - Lookback Candles | Minimum number of candles to constitute a range | 10 |
| FVG - Range - ATR Period | ATR period used for range and breakout calculations | 14 |
| FVG - Range - ATR Multiplier | Range high-to-low must be less than X × ATR to be valid | 1.5 |

### Breakout Detection
| Input | Description | Default |
|-------|-------------|---------|
| FVG - Breakout - ATR Multiplier | Breakout candle body must be greater than X × ATR | 1.0 |

---

## Behaviour

### FVG Validity (Range + Breakout Filter)
Only FVGs that form after a breakout from a range are considered valid:

1. Look back `FVG - Range - Lookback Candles` candles before the FVG candle
2. Calculate the highest high and lowest low of that lookback window
3. If `(highest high - lowest low) < FVG - Range - ATR Multiplier × ATR` → range is valid (price was contained)
4. The candle immediately before the FVG must be an expansion candle: `candle body > FVG - Breakout - ATR Multiplier × ATR`
5. The breakout candle closes outside the range high (bullish) or range low (bearish)
6. FVG must form in the same direction as the breakout

FVGs that appear inside a range or without a preceding expansion candle are ignored.

### Minimum Size Filter
- Gap size = distance between Candle 1 high and Candle 3 low (bullish), or Candle 1 low and Candle 3 high (bearish)
- If gap size < `FVG - Filter - Minimum Size (pips)` → discard

### Mitigation (Fill Tracking)
- When price enters a FVG, the rectangle shrinks dynamically:
  - **Bullish FVG**: bottom edge rises as price fills from below
  - **Bearish FVG**: top edge drops as price fills from above
- When the FVG is **fully filled**, the rectangle disappears
- No internal memory of filled FVGs is retained

### Visual Display
- FVGs drawn as filled rectangles on the chart
- Only the FVGs matching the **current chart timeframe** are drawn
- Rectangle spans from the FVG open time to the current bar (extends right as time progresses)
- Bullish FVGs = green rectangle
- Bearish FVGs = red rectangle

---

## Timeframe Monitoring

The EA monitors FVGs internally across all 7 timeframes:

| Timeframe | Drawn on Chart | Monitored Internally |
|-----------|---------------|----------------------|
| M1        | Only when chart is M1 | Always |
| M5        | Only when chart is M5 | Always |
| M15       | Only when chart is M15 | Always |
| M30       | Only when chart is M30 | Always |
| H1        | Only when chart is H1 | Always |
| H4        | Only when chart is H4 | Always |
| D1        | Only when chart is D1 | Always |

Internal monitoring is the foundation for future multi-timeframe bias and trade logic modules.

---

## Module Toggle

| Input | Description | Default |
|-------|-------------|---------|
| FVG - Enable Module | Enable or disable the entire FVG module | true |

---

## Notes

- All ATR calculations use the timeframe of the FVG being evaluated (not the chart timeframe)
- The range and breakout logic is fully ATR-relative, making it adaptive across all timeframes without hardcoded pip values
- This module is observation-only at this stage — no trade decisions are made based on FVGs yet
