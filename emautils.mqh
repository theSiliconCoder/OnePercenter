#include "liquidityutils.mqh"


int    FastEMA_Period  = 5;
int    MidEMA_Period   = 9;
int    SlowEMA_Period  = 50;
int    ATR_Period      = 14;
double ATR_Percent     = 5.0;   // 5% ATR threshold


ENUM_TIMEFRAMES timeFrameMain = PERIOD_M15;
ENUM_TIMEFRAMES timeFrameAlt = PERIOD_H1;

int handleEMAfast, handleEMAmid, handleEMAslow, handleATR;
double emaFast[], emaMid[], emaSlow[], atrValue[2];

int handleDayEmaFast, handleDayEmaMid, handleDayEmaSlow;
double dayEmaFast[], dayEmaMid[], dayEmaSlow[];

int barsCntSoFar = 0;

bool inPosition = false;
int signalCntToday = 0;
bool positionClosedFlag = false;

enum TradeSignal{
   BUY,
   SELL,
   NONE
};

enum MostRecentCross{
   CROSS_BUY,
   CROSS_SELL,
   CROSS_NONE
};

TradeSignal currentSignal = NONE;
MostRecentCross recent5_9Cross = CROSS_NONE;
MostRecentCross recent5_50Cross = CROSS_NONE;


void initEma(){
   ArraySetAsSeries(emaFast,true);
   ArraySetAsSeries(emaMid,true);
   ArraySetAsSeries(emaSlow,true);
   ArraySetAsSeries(dayEmaFast,true);
   ArraySetAsSeries(dayEmaMid,true);
   ArraySetAsSeries(dayEmaSlow,true);

   // Get EMA values for current candle (index 1 to avoid current forming bar)
   handleEMAfast = iMA(_Symbol, timeFrameMain, FastEMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   handleEMAmid = iMA(_Symbol, timeFrameMain, MidEMA_Period,  0, MODE_EMA, PRICE_CLOSE);
   handleEMAslow = iMA(_Symbol, timeFrameMain, SlowEMA_Period, 0, MODE_EMA, PRICE_CLOSE);

   handleDayEmaFast = iMA(_Symbol, timeFrameAlt, FastEMA_Period,  0, MODE_SMA, PRICE_CLOSE);
   handleDayEmaMid = iMA(_Symbol, timeFrameAlt, MidEMA_Period,  0, MODE_SMA, PRICE_CLOSE);
   handleDayEmaSlow = iMA(_Symbol, timeFrameAlt, SlowEMA_Period, 0, MODE_SMA, PRICE_CLOSE);

   // Get ATR value
   handleATR = iATR(_Symbol, timeFrameMain, ATR_Period);

   if(handleEMAfast==INVALID_HANDLE || handleEMAmid==INVALID_HANDLE ||
      handleEMAslow==INVALID_HANDLE || handleATR==INVALID_HANDLE || handleDayEmaFast==INVALID_HANDLE ||
      handleDayEmaMid == INVALID_HANDLE || handleDayEmaSlow == INVALID_HANDLE)
   {
      Print("Error creating indicator handles");
      return;
   }
   Print("EMA + ATR Signal Generator Initialized");
}




void checkForTrade(StrategyConfig &sConfig){

   

   // Get latest values (shift 1 = last closed candle)
   if(CopyBuffer(handleEMAfast, 0, 0, 14, emaFast) <= 0) return;
   if(CopyBuffer(handleEMAmid,  0, 0, 14, emaMid)  <= 0) return;
   if(CopyBuffer(handleEMAslow, 0, 0, 14, emaSlow) <= 0) return;
   if(CopyBuffer(handleATR,     0, 0, 2, atrValue)<= 0) return;

   if(CopyBuffer(handleDayEmaFast, 0, 0, 14, dayEmaFast) <= 0) {
      Print("SIGNAL INVALID: Daily 5 EMA Data Unvavailable");
      return;}
   if(CopyBuffer(handleDayEmaMid, 0, 0, 14, dayEmaMid) <= 0) {
      Print("SIGNAL INVALID: Daily 9 EMA Data Unvavailable");
      return;}
   if(CopyBuffer(handleDayEmaSlow,  0, 0, 14, dayEmaSlow)  <= 0) {
      Print("SIGNAL INVALID: Daily 50 EMA  Data Unvavailable");
      return;}

   double atrThreshold = (ATR_Percent / 100.0) * atrValue[0];
  

   // Print("ATR Threshold: ", atrThreshold);

   // BUY Condition: ema5 > ema9 by at least 5% ATR, and ema9 > ema50
   

   double emaFastVal = NormalizeDouble(emaFast[0], _Digits);
   double emaMidVal = NormalizeDouble(emaMid[0], _Digits);
   double emaSlowVal = NormalizeDouble(emaSlow[0], _Digits);

   double dayEmaFastVal = NormalizeDouble(dayEmaFast[0], _Digits);
   double dayEmaMidVal = NormalizeDouble(dayEmaMid[0], _Digits);
   double dayEmaSlowVal = NormalizeDouble(dayEmaSlow[0], _Digits);

   bool signalSource = sConfig.entryStrategy == ENTRY_HYBRID ? true : false;
   
   // checkFor5_50Crossing(signalSource); 
   checkFor5_9Crossing(false);

   if (!inPosition && (emaFastVal > emaMidVal)  &&  recent5_9Cross == CROSS_BUY && signalCntToday <= 0)
   {
      
      if(sConfig.validateEntries){
         EntryDataToValidate entryData(true, emaFastVal, emaMidVal, emaSlowVal, dayEmaFastVal, dayEmaMidVal, dayEmaSlowVal, atrThreshold, emaFast);
         if(!validateEntry(entryData, sConfig)){ 
            recent5_9Cross = CROSS_NONE;
            return;
         }
      } 

      if(countPositions(POSITION_TYPE_BUY) <= 0){
         Print("BUY Signal: EMA5=", emaFastVal, " | EMA9=", emaMidVal, " | EMA50=", emaSlowVal);
         // open buy
         
         // double riskMargin = 0.0050;
         // double openPrice = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_BID), _Digits);
         // double sl = openPrice - riskMargin;

         double sl = getStopPrice(true, timeFrameMain, atrValue[1]);
         if(sl == -1) return;
         placeOrder(true, sl, sConfig);

         inPosition = true;
         signalCntToday = 1;
         barsCntSoFar = 0;
         recent5_9Cross = CROSS_NONE;
         isBreakEvenTriggered = false;
      }

      // Print("EMA 5 > 9: EMA5= ", emaFastVal, " | EMA9= ", emaMidVal);

     
   } else {

      if(inPosition && barsCntSoFar >= 2){
         // bool exitPos = isMomentumLow(POSITION_TYPE_BUY, emaFast);

         // if(exitPos && countPositions(POSITION_TYPE_BUY) >= 0){
         //    // close existing BUY
         //    closeAllPositions(POSITION_TYPE_BUY);
         //    positionClosedFlag = true;
         // }

         if(isBreakEvenTriggered){
            checkFor5_9Crossing(false);

            if (recent5_9Cross == CROSS_SELL && (emaFastVal < emaMidVal)){
               recent5_9Cross = CROSS_NONE;
               if(countPositions(POSITION_TYPE_BUY) >= 0){
                  // close existing BUY
                  closeAllPositions(POSITION_TYPE_BUY);
                  positionClosedFlag = true;
               }
            }
         }

         

      }

     

      
   }


   // SELL Condition: ema5 < ema9 by at least 5% ATR, and ema9 < ema50 //  && (dayEmaSlowVal > dayEmaFastVal)
   
   if (!inPosition && (emaMidVal > emaFastVal) &&  recent5_9Cross == CROSS_SELL && signalCntToday <= 0)
   {

      if(sConfig.validateEntries){
         EntryDataToValidate entryData(false, emaFastVal, emaMidVal, emaSlowVal, dayEmaFastVal, dayEmaMidVal, dayEmaSlowVal, atrThreshold, emaFast);
         if(!validateEntry(entryData, sConfig)) { 
            recent5_9Cross = CROSS_NONE;
            return;
         }
      } 

      
      if(countPositions(POSITION_TYPE_SELL) <= 0){
         Print("SELL Signal: EMA5=", emaFastVal, " EMA9=", emaMidVal, " EMA50=", emaSlowVal);
         // open SELL
         double sl = getStopPrice(false, timeFrameMain, atrValue[1]);
         if(sl == -1) return;
         placeOrder(false, sl, sConfig);

         inPosition = true;
         signalCntToday = 1;
         barsCntSoFar = 0;
         recent5_9Cross = CROSS_NONE;
         isBreakEvenTriggered = false;
      }

      
   }else {

      // if ((emaMidVal - emaFastVal) < atrThreshold) {
      //    Print("EMA 9 -5 less than atrthreshold: EMA 9 - 5= ", emaMidVal - emaFastVal, " | Threshold ", atrThreshold);
      //    return;
      // }

      // if ((emaSlowVal - emaMidVal) <= atrValue[0]*0.6) {
      //    Print("EMA 50-9 lessthn/equal to atrthreshold: EMA 50- 9= ", emaSlowVal - emaMidVal, " | Threshold ", atrValue[0]*0.6);
      //    return;
      // }

      if(inPosition && barsCntSoFar >= 2){
         // bool exitPos = isMomentumLow(POSITION_TYPE_BUY, emaFast);

         // if(exitPos && countPositions(POSITION_TYPE_BUY) >= 0){
         //    // close existing BUY
         //    closeAllPositions(POSITION_TYPE_BUY);
         //    positionClosedFlag = true;
         // }

         if(isBreakEvenTriggered){
             checkFor5_9Crossing(false);

            if (recent5_9Cross == CROSS_BUY && (emaFastVal > emaMidVal)){
               recent5_9Cross = CROSS_NONE;
               if(countPositions(POSITION_TYPE_SELL) >= 0){
                  // close existing sell
                  closeAllPositions(POSITION_TYPE_SELL);
                  positionClosedFlag = true;
               }
            }
         }

        

      }

      
   }

}

void checkFor5_9Crossing(bool checkDailyOnly){
   if(checkDailyOnly){
      if (CrossAbove(dayEmaFast, dayEmaMid) && recent5_9Cross != CROSS_BUY ){
         Print("Day EMA 5 Cross Above 9 Event: EMA5= ", dayEmaFast[0], "| EMA9= ", dayEmaMid[0]);
         recent5_9Cross = CROSS_BUY;
      }
   
      if(CrossBelow(dayEmaFast, dayEmaMid) && recent5_9Cross != CROSS_SELL){
         Print("Day EMA 5 Cross Below 9 Event: EMA5= ", dayEmaFast[0], "| EMA9= ", dayEmaMid[0]);
         recent5_9Cross = CROSS_SELL;
      }
   }
   else {
      if (CrossAbove(emaFast, emaMid) && recent5_9Cross != CROSS_BUY ){
         Print("EMA 5 Cross Above 9 Event: EMA5= ", emaFast[0], "| EMA9= ", emaMid[0]);
         recent5_9Cross = CROSS_BUY;
      }
   
      if(CrossBelow(emaFast, emaMid) && recent5_9Cross != CROSS_SELL){
         Print("EMA 5 Cross Below 9 Event: EMA5= ", emaFast[0], "| EMA9= ", emaMid[0]);
         recent5_9Cross = CROSS_SELL;
      }
   }

   
}

void checkFor5_50Crossing(bool checkDailyEma){
   if (CrossAbove(emaFast, emaSlow) && recent5_50Cross != CROSS_BUY ){
      Print("EMA 5 Cross Above 50 Event: EMA5= ", emaFast[0], "| EMA50= ", emaSlow[0]);
      recent5_50Cross = CROSS_BUY;
   }

   if(CrossBelow(emaFast, emaSlow) && recent5_50Cross != CROSS_SELL){
      Print("EMA 5 Cross Below 50 Event: EMA5= ", emaFast[0], "| EMA50= ", emaSlow[0]);
      recent5_50Cross = CROSS_SELL;
   }

   if(checkDailyEma){
      if (CrossAbove(dayEmaFast, dayEmaSlow) && recent5_50Cross != CROSS_BUY ){
         Print("Day EMA 5 Cross Above 50 Event: EMA5= ", dayEmaFast[0], "| EMA50= ", dayEmaSlow[0]);
         recent5_50Cross = CROSS_BUY;
      }
   
      if(CrossBelow(dayEmaFast, dayEmaSlow) && recent5_50Cross != CROSS_SELL){
         Print("Day EMA 5 Cross Below 50 Event: EMA5= ", dayEmaFast[0], "| EMA50= ", dayEmaSlow[0]);
         recent5_50Cross = CROSS_SELL;
      }
   }
}



bool isTimeToExit(ENUM_POSITION_TYPE posType, double&emaArr[]){
   Print("EMA 5 (2) vs (1): EMA5 2= ", emaArr[2], "| EMA5 1= ", emaArr[1]);
   return posType == POSITION_TYPE_BUY ? emaArr[2] > emaArr[1] : emaArr[2] < emaArr[1];
}


bool isSlopeSteep(ENUM_POSITION_TYPE posType, double&emaArr[]){
   double atrThreshold = (ATR_Percent / 100.0) * atrValue[0];
   // Print("EMA 5 (1) vs (0): EMA5 2= ", emaArr[3], "| EMA5 1= ", emaArr[0]);
   return posType == POSITION_TYPE_BUY ? emaArr[0] > emaArr[3] + atrThreshold  : emaArr[0] < emaArr[3] - atrThreshold;
}


bool CrossAbove(double &fast[], double &slow[], int barShift = 2)
{
   if(barsCntSoFar < barShift) return false;

    return (fast[barShift] < slow[barShift])   // fast was below slow
        && (fast[0]   > slow[0]);    // fast is now above slow
}

bool CrossBelow(double &fast[], double &slow[], int barShift = 2)
{
   if(barsCntSoFar < barShift) return false;

    return (fast[barShift] > slow[barShift])   // fast was above slow
        && (fast[0]   < slow[0]);    // fast is now below slow
}



int countPositions(ENUM_POSITION_TYPE positionType){

   int openPositions = 0;
   // --- Count positions ---
   for (int i = 0; i < PositionsTotal(); i++)
   {
      if (PositionGetTicket(i))
      {
         if (PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            if (type == positionType)  openPositions++;
         }
      }
   }

   return openPositions;

}