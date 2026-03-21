
// #include "sr_routines.mqh"



//+------------------------------------------------------------------+
//| Market Classifier for GBP/USD (MQL5 version)                     |
//+------------------------------------------------------------------+
#include <Indicators/Trend.mqh>
#include <Indicators/Oscilators.mqh>
// #include <Indicators/Bands.mqh>

enum MARKET_TYPE {
    UNKNOWN,
    TRENDING_VOLATILE,
    RANGING_CHOPPY,
    DOUBLETOUCH
};

//+------------------------------------------------------------------+
//| Market Classification using proper MQL5 indicator calls          |
//+------------------------------------------------------------------+
MARKET_TYPE ClassifyMarket(int barsToAnalyze = 14) {

   ENUM_TIMEFRAMES timeframe = PERIOD_H1;

    // Adjust parameters based on timeframe
    double volatilityFactor = 1.0;
    int adxPeriod = 14;
    double adxThreshold = 20.0;
    double atrRatioThreshold = 0.005;
    int bollingerPeriod = 20;
    double bollingerDeviation = 2.0;
    int rsiPeriod = 14;
    double rsiThreshold = 60.0;
    int doubleTouchLookback = 10;
    double doubleTouchThreshold = 0.0025;
    
    // Adjust parameters for higher timeframes
    if(timeframe >= PERIOD_H1) {
        volatilityFactor = 1.5;
        adxThreshold = 25.0;
        atrRatioThreshold = 0.003;
        doubleTouchThreshold = 0.0020;
    }
    if(timeframe >= PERIOD_H4) {
        volatilityFactor = 2.0;
        adxThreshold = 30.0;
        atrRatioThreshold = 0.002;
        doubleTouchThreshold = 0.0015;
    }
    if(timeframe >= PERIOD_D1) {
      volatilityFactor = 3.0;
      adxThreshold = 35.0;
      atrRatioThreshold = 0.01;
      doubleTouchThreshold = 0.0015;
   }
    
    // Create indicator handles
    int adxHandle = iADX(_Symbol, timeframe, adxPeriod);
    int atrHandle = iATR(_Symbol, timeframe, 14);
    int rsiHandle = iRSI(_Symbol, timeframe, rsiPeriod, PRICE_CLOSE);
    int bollingerHandle = iBands(_Symbol, timeframe, bollingerPeriod, 0, bollingerDeviation, PRICE_CLOSE);
    
    // Get indicator values
    double adxMain[1], adxPlusDI[1], adxMinusDI[1];
    double atr[1];
    double rsi[1];
    double upperBand[1], lowerBand[1], middleBand[1];
    
    if(CopyBuffer(adxHandle, 0, 0, 1, adxMain) != 1 ||
       CopyBuffer(adxHandle, 1, 0, 1, adxPlusDI) != 1 ||
       CopyBuffer(adxHandle, 2, 0, 1, adxMinusDI) != 1 ||
       CopyBuffer(atrHandle, 0, 0, 1, atr) != 1 ||
       CopyBuffer(rsiHandle, 0, 0, 1, rsi) != 1 ||
       CopyBuffer(bollingerHandle, 1, 0, 1, upperBand) != 1 ||
       CopyBuffer(bollingerHandle, 2, 0, 1, lowerBand) != 1 ||
       CopyBuffer(bollingerHandle, 0, 0, 1, middleBand) != 1) {
        Print("Error copying indicator buffers");
        return UNKNOWN;
    }
    
    double atrRatio = atr[0] / SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    // Check for Double Touch pattern
    bool doubleTouch = CheckDoubleTouch(timeframe, doubleTouchLookback, doubleTouchThreshold);
    
    // Market classification logic
   //  if(doubleTouch) {
   //      return DOUBLETOUCH;
   //  }
    
    // Check for trending/volatile conditions
    bool isTrending = adxMain[0] > adxThreshold && (adxPlusDI[0] > adxMinusDI[0] * 1.2 || adxMinusDI[0] > adxPlusDI[0] * 1.2);
    bool isVolatile = atrRatio > (atrRatioThreshold * volatilityFactor);
    
    if(isTrending || isVolatile) {
        return TRENDING_VOLATILE;
    }
    
    // Check for ranging/choppy conditions
    bool isRanging = adxMain[0] < (adxThreshold * 0.7);
    bool isChoppy = (upperBand[0] - lowerBand[0]) < (middleBand[0] * 0.03 * volatilityFactor) && 
                   rsi[0] > (100 - rsiThreshold) && rsi[0] < rsiThreshold;
    
    if(isRanging || isChoppy) {
        return RANGING_CHOPPY;
    }
    
    return UNKNOWN;
}

//+------------------------------------------------------------------+
//| Enhanced Double Touch Pattern Detection                          |
//| Detects:                                                         |
//| - Double Top (M pattern)                                         |
//| - Double Bottom (W pattern)                                      |
//| - Uses fractal-like detection for peaks and troughs              |
//+------------------------------------------------------------------+

bool CheckDoubleTouch(ENUM_TIMEFRAMES timeframe, int lookback, double threshold) {
    // Find the most recent significant peak and trough
    int recentPeakBar = FindRecentPeak(timeframe, lookback);
    int recentTroughBar = FindRecentTrough(timeframe, lookback);
    
    // Check for Double Top (M pattern)
    if(recentPeakBar > 0 && recentPeakBar < lookback/2) {
        int secondPeakBar = FindSecondPeak(timeframe, recentPeakBar, lookback);
        if(secondPeakBar > 0) {
            double firstPeak = iHigh(_Symbol, timeframe, recentPeakBar);
            double secondPeak = iHigh(_Symbol, timeframe, secondPeakBar);
            if(MathAbs(firstPeak - secondPeak) <= threshold) {
                double valleyLow = FindValleyLow(timeframe, recentPeakBar, secondPeakBar);
                if((firstPeak - valleyLow) >= (threshold * 2)) {
                    return true;
                }
            }
        }
    }
    
    // Check for Double Bottom (W pattern)
    if(recentTroughBar > 0 && recentTroughBar < lookback/2) {
        int secondTroughBar = FindSecondTrough(timeframe, recentTroughBar, lookback);
        if(secondTroughBar > 0) {
            double firstTrough = iLow(_Symbol, timeframe, recentTroughBar);
            double secondTrough = iLow(_Symbol, timeframe, secondTroughBar);
            if(MathAbs(firstTrough - secondTrough) <= threshold) {
                double peakHigh = FindPeakHigh(timeframe, recentTroughBar, secondTroughBar);
                if((peakHigh - firstTrough) >= (threshold * 2)) {
                    return true;
                }
            }
        }
    }
    
    return false;
}




//+------------------------------------------------------------------+
//| Find the most recent significant peak                           |
//+------------------------------------------------------------------+
int FindRecentPeak(ENUM_TIMEFRAMES timeframe, int lookback) {
   for(int i = 3; i < lookback; i++) {
       double high = iHigh(NULL, timeframe, i);
       if(high > iHigh(NULL, timeframe, i-1) && 
          high > iHigh(NULL, timeframe, i-2) && 
          high > iHigh(NULL, timeframe, i+1) && 
          high > iHigh(NULL, timeframe, i+2)) {
           return i;
       }
   }
   return -1;
}

//+------------------------------------------------------------------+
//| Find the most recent significant trough                         |
//+------------------------------------------------------------------+
int FindRecentTrough(ENUM_TIMEFRAMES timeframe, int lookback) {
   for(int i = 3; i < lookback; i++) {
       double low = iLow(NULL, timeframe, i);
       if(low < iLow(NULL, timeframe, i-1) && 
          low < iLow(NULL, timeframe, i-2) && 
          low < iLow(NULL, timeframe, i+1) && 
          low < iLow(NULL, timeframe, i+2)) {
           return i;
       }
   }
   return -1;
}

//+------------------------------------------------------------------+
//| Find second peak forming the M pattern                           |
//+------------------------------------------------------------------+
int FindSecondPeak(ENUM_TIMEFRAMES timeframe, int firstPeakBar, int lookback) {
   for(int i = firstPeakBar + 2; i < lookback; i++) {
       double high = iHigh(NULL, timeframe, i);
       if(high > iHigh(NULL, timeframe, i-1) && 
          high > iHigh(NULL, timeframe, i-2) && 
          high > iHigh(NULL, timeframe, i+1) && 
          high > iHigh(NULL, timeframe, i+2)) {
           return i;
       }
   }
   return -1;
}

//+------------------------------------------------------------------+
//| Find second trough forming the W pattern                         |
//+------------------------------------------------------------------+
int FindSecondTrough(ENUM_TIMEFRAMES timeframe, int firstTroughBar, int lookback) {
   for(int i = firstTroughBar + 2; i < lookback; i++) {
       double low = iLow(NULL, timeframe, i);
       if(low < iLow(NULL, timeframe, i-1) && 
          low < iLow(NULL, timeframe, i-2) && 
          low < iLow(NULL, timeframe, i+1) && 
          low < iLow(NULL, timeframe, i+2)) {
           return i;
       }
   }
   return -1;
}

//+------------------------------------------------------------------+
//| Find the lowest point between two peaks                          |
//+------------------------------------------------------------------+
double FindValleyLow(ENUM_TIMEFRAMES timeframe, int peak1Bar, int peak2Bar) {
   double lowest = DBL_MAX;
   int startBar = MathMin(peak1Bar, peak2Bar);
   int endBar = MathMax(peak1Bar, peak2Bar);
   
   for(int i = startBar; i <= endBar; i++) {
       double low = iLow(NULL, timeframe, i);
       if(low < lowest) lowest = low;
   }
   return lowest;
}

//+------------------------------------------------------------------+
//| Find the highest point between two troughs                       |
//+------------------------------------------------------------------+
double FindPeakHigh(ENUM_TIMEFRAMES timeframe, int trough1Bar, int trough2Bar) {
   double highest = -DBL_MAX;
   int startBar = MathMin(trough1Bar, trough2Bar);
   int endBar = MathMax(trough1Bar, trough2Bar);
   
   for(int i = startBar; i <= endBar; i++) {
       double high = iHigh(NULL, timeframe, i);
       if(high > highest) highest = high;
   }
   return highest;
}