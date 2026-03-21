//+------------------------------------------------------------------+
//|                                               liquiditymanip.mq5 |
//|                                  Copyright 2025, theSiliconCoder |
//|                                                 https://mql5.com |
//| 07.08.2025 - Initial release                                     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, theSiliconCoder"
#property link      "https://mql5.com"
#property version   "1.00"


#include "emautils.mqh"
#include "MarketClassifier.mqh"
//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+

MARKET_TYPE marketTypeFilter[4];
bool isTrendingMarket = true;
int marketTypeArrSize = 0;

StrategyConfig sConfig;

int OnInit()
   {
//---
    sConfig.checkDayBar = true;
    sConfig.checkDayEmaFastvsSlow = true;
    sConfig.checkEmaGap = false;
    sConfig.checkEmaMomentum = false;

    sConfig.checkKillZone =  false;
    sConfig.invalidKz[0] = KILLZONE_ASIA;
    sConfig.invalidKz[1] = KILLZONE_UNKNOWN;
    sConfig.invalidKz[2] = KILLZONE_UNKNOWN;

    sConfig.checkVolume = true;
    sConfig.checkForBo = true;

    sConfig.entryStrategy = ENTRY_MAIN;
    sConfig.exitStrategy = ExitStrategy::TRAILING;  // implemented

    sConfig.isNyOnly = false;
    sConfig.checkTrendingMarket = false;

    sConfig.validateEntries = true;

    initEma();
//---
    return(INIT_SUCCEEDED);
   }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+

void OnDeinit(const int reason)
   {
//---
    // Release indicator handles
   IndicatorRelease(handleEMAfast);
   IndicatorRelease(handleEMAmid);
   IndicatorRelease(handleEMAslow);
   IndicatorRelease(handleATR);
   }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+

SweepData gSweepData;



void OnTick()
   {
    
      
      
      

      // if (!inPosition) signalGen(gSweepData);

      if(PositionsTotal()) {
         // inPosition = true;
         // positionMonitor(sConfig);
      }

      // int bars = Bars(_Symbol, mainTf); 

      int bars = Bars(_Symbol, timeFrameMain); 
   
      // on each new bar, monitor chart for breakout
      if (barsTotal != bars)
      {
         barsTotal = bars; // update barsTotal with newly drawn bar/candle

         // onNewBar();
         barsCntSoFar++;

         checkForTrade(sConfig);

         if(PositionsTotal() <= 0) {  // ensures no close and open happen on the same bar
            inPosition = false;
            // Print("Reset inPosition to: ", inPosition);
         }

         // Print("New Hour Bar, UTC + 1 TIME: ", GetCurrentHour());
         if(GetCurrentHour() >= 1 && GetCurrentHour() <= 3 && signalCntToday > 0) {
            signalCntToday = todaysTpCnt = 0; // reset signal cnt for today
            Print("Reset Signal Count Today to: ", signalCntToday);
         }

         // if(marketTypeArrSize >= 3) {
         //    marketTypeArrSize = 0;
         //    if(marketTypeFilter[0] == TRENDING_VOLATILE 
         //       && marketTypeFilter[1] == TRENDING_VOLATILE 
         //       && marketTypeFilter[2] == TRENDING_VOLATILE
         //    ){
         //       isTrendingMarket = true;
         //       Print("Market Trending");
         //    }else {
         //       isTrendingMarket = false;
         //       Print("Market NOT Trending");
         //    }
         // }
         // else marketTypeFilter[marketTypeArrSize++] = ClassifyMarket();
         
         
      }
    
   }

//+------------------------------------------------------------------+


void onNewBar(){

   if(PositionsTotal() <= 0) {  // ensures no close and open happen on the same bar
      inPosition = false;
   }

   Print("New Hour Bar, UTC + 1 TIME: ", GetCurrentHour());

   // if (GetCurrentHour() == 19 && PositionsTotal()) {
   //    closeAllPositions(POSITION_TYPE_BUY);
   //    closeAllPositions(POSITION_TYPE_SELL);
   //  }

}

