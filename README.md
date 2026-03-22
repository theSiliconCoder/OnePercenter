# Adaptive EMA + Volatility Strategy (Market-Aware Execution Layer for MT5)

## Overview

This project implements a **market-aware trading strategy in MetaTrader 5 (MQL5)** that combines:

- EMA-based momentum signals
- ATR-based volatility filtering
- Market regime classification
- Configurable entry validation pipeline

While the current implementation executes **directional trades**, the architecture is designed with a **market-making mindset**, focusing on _when to participate_, _when to stay out_, and _how to adapt to changing market conditions_.

---

## Core Idea

Rather than blindly trading every signal, the system acts as a **selective liquidity participant**:

> Only engage the market when **structure, momentum, and volatility align**

This is closer to how systematic trading desks operate:

- Filter noise
- Avoid adverse conditions
- Trade only when edge is statistically favorable

---

## Strategy Components

### 1. Momentum Engine (EMA Crossovers)

- EMA(5), EMA(9), EMA(50)
- Primary trigger: **EMA 5 / EMA 9 crossover**
- EMA 50 provides higher-level trend context

This captures **short-term directional inefficiencies**.

---

### 2. Volatility Filter (ATR)

- ATR is used to enforce **minimum separation between EMAs**
- Prevents entries during:
  - Low volatility
  - Microstructure noise

This mimics a **spread/edge filter** in market making:

> No volatility = no edge

---

### 3. Market Regime Classification

The system continuously classifies the market into regimes such as:

- Trending volatile
- Non-trending / ranging

```cpp
marketTypeFilter[3] → rolling classification
isTrendingMarket → derived state
```

Only after consistent classification (3 confirmations) does the system adapt behavior.

This is critical because:

> Strategy performance is regime-dependent

---

### 4. Configurable Entry Validation Layer

A flexible validation pipeline (`StrategyConfig`) allows enabling/disabling filters:

- Daily EMA alignment
- EMA gap / momentum checks
- Volume conditions
- Breakout confirmation
- Killzone filtering (session-based participation)

This creates a **plug-and-play research framework** for testing hypotheses.

---

### 5. Multi-Timeframe Awareness

- Lower timeframe → entry timing
- Daily EMAs → structural bias

This reduces:

- False breakouts
- Counter-trend entries

---

## Entry Logic

### BUY

- EMA(5) crosses above EMA(9)
- Momentum confirmed (EMA alignment)
- Signal passes validation pipeline
- No active position
- Volatility threshold satisfied

### SELL

- EMA(5) crosses below EMA(9)
- Momentum confirmed
- Validation pipeline passes
- Volatility threshold satisfied

---

## Execution Philosophy (Market-Making Angle)

Although trades are directional, the system reflects key **market-making principles**:

### 1. Selective Participation

- Trades are limited (e.g. 1 signal/day)
- Avoids overtrading in noisy environments

### 2. Regime Awareness

- Strategy adapts based on detected market conditions
- Avoids deploying the same logic in all environments

### 3. Edge Filtering

- ATR acts as a proxy for:
  - Spread viability
  - Price movement potential

### 4. Event-Driven Execution

- Runs on **new bar events**, not every tick
- Reduces reaction to microstructure noise

---

## Risk Management

### Stop Loss

- ATR-based dynamic stop
- Adjusts to current volatility

### Trade Constraints

- One position per direction
- Signal throttling (per day)

### Exit Logic

- Break-even tracking
- Opposite EMA crossover triggers exit after minimum holding period

---

## System Architecture Highlights

- Modular design (`StrategyConfig`)
- Indicator handles reused efficiently
- State tracking:
  - `inPosition`
  - `recent cross events`
  - `bars since entry`

- Separation of:
  - Signal generation
  - Validation
  - Execution

---

## Backtesting Notes

- Designed for **tick-driven environments (`OnTick`)**
- Entry decisions executed on **new bar formation**
- Results depend on:
  - Broker data quality
  - Tick model used

Recommended:

- “Every tick based on real ticks”

---

## Limitations

- Directional execution only (not true bid/ask quoting)
- No inventory management
- No spread capture or order book interaction
- No latency modeling

---

## Future Work (Towards True Market Making)

This system can evolve into a more **market-making / execution-focused model** by adding:

- Two-sided quoting (bid/ask placement)
- Inventory/risk skew management
- Order book / depth-of-market signals
- Tick-level microstructure features
- Latency-aware execution logic

---

## Conclusion

This project demonstrates a transition from:

> Simple indicator strategy → **market-aware trading system**

It emphasizes:

- Regime filtering
- Volatility-aware participation
- Configurable research framework

and serves as a foundation for building more advanced:

- Systematic trading strategies
- Execution engines
- Market-making systems

---
