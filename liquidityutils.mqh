#include "MoniePilot.mqh"
#include "DipBuyer.mqh"
#include <Trade/DealInfo.mqh>
#include <Trade/OrderInfo.mqh>
#include <Trade/PositionInfo.mqh>


ENUM_TIMEFRAMES mainTf = PERIOD_H4;
MoniePilot::Indicators::SuperTrend HourTrend(PERIOD_M30); 
MoniePilot::Indicators::ATR atr(mainTf);

bool isDebug = false;
bool isBreakEvenTriggered = false;

enum ExitStrategy {
   FIXED,
   TRAILING,
   HYBRID
};

enum EntryStrategy {
   ENTRY_MAIN,
   ENTRY_BIAS,
   ENTRY_HYBRID
};


enum KILLZONECODE{
   KILLZONE_ASIA,
   KILLZONE_LONDON,
   KILLZONE_NEWYORK,
   KILLZONE_UNKNOWN
};

enum SESSIONCODE{
   ASIA_SESSION,
   LONDON_SESSION,
   NEWYORK_SESSION,
   UNDEFINED_SESSION
};

struct SessionParams{
   double sessionLow;
   double sessionHigh;
   SESSIONCODE sessionCode;

   SessionParams(){
      sessionHigh = sessionLow = 0;
      sessionCode = UNDEFINED_SESSION;
   };

   SessionParams(const SessionParams &sp){
      this = sp;
   }
};


struct StrategyConfig{
   EntryStrategy entryStrategy;
   ExitStrategy exitStrategy;
   bool checkVolume;
   bool checkKillZone;
   KILLZONECODE invalidKz[3];
   bool isNyOnly;
   bool checkForBo;
   bool checkDayBar;
   bool checkEmaGap;
   bool checkEmaMomentum;
   bool checkTrendingMarket;
   bool checkBoCandlePressure;
   bool validateEntries;
   bool checkDayEmaFastvsSlow;
   
};

// IN UTC+1 format 1
// int AsiaSession[] =  {1,2,3,4,5,6};
// int LondonSession[] = {8,9,10,11};
// int NewYorkSession[] = {12,13,14,15,16,17};
int AsiaSession[] =  {1,2,3,4};
int LondonSession[] = {5,6,7,8,9,10,11};
int NewYorkSession[] = {12,13,14,15,16,17,18};


KILLZONECODE zonesProfitableToday[3];
int todaysTpCnt = 0;

double breakPoint = DBL_MAX;
double bearishBreakPt = DBL_MIN;



int GetCurrentHour()
{
   datetime now = TimeCurrent();  // Broker server time (usually UTC)
   MqlDateTime dt;
   TimeToStruct(now, dt);

   int utc1Hour = (dt.hour + 1) % 24;  // Convert to UTC+1 to match trading view/local time

   return utc1Hour; // range 0 ... 23
}


KILLZONECODE checkActiveKillZone()
{
   int currHour = GetCurrentHour();

   if (currHour >= AsiaSession[0] && currHour <= AsiaSession[ArraySize(AsiaSession)-1]) {
      
      for (int i = 0; i < ArraySize(zonesProfitableToday); i++)
      {
         zonesProfitableToday[i] = -1; // reset profited zones
      }
      todaysTpCnt = 0;

      breakPoint = DBL_MAX;
      bearishBreakPt = DBL_MIN;

      return KILLZONE_ASIA;
   }  // First 4H block
   else if (currHour >= LondonSession[0] && currHour <= LondonSession[ArraySize(LondonSession)-1]) return KILLZONE_LONDON;  // Second 4H block
   else if (currHour >= NewYorkSession[0] && currHour <= NewYorkSession[ArraySize(NewYorkSession)-1]) return KILLZONE_NEWYORK;  // Final 4H block (before NY close)
   else return KILLZONE_UNKNOWN;  // Outside defined trading session blocks
}

SessionParams getPrevSessionParams(KILLZONECODE &killZone){

   SessionParams sessionParams;

   if(killZone == KILLZONE_UNKNOWN || killZone == KILLZONE_ASIA) return sessionParams;

   int searchStartIndex;
   int searchEndIndex;

   ENUM_TIMEFRAMES wtf = PERIOD_H1;
   
   // Initialize anchor times
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.min = 0;
   dt.sec = 0;
 

   datetime fromTime = D'1990.12.16 06:00';
   datetime toTime = D'1990.12.16 06:00';

   switch (killZone)
   {
      case KILLZONE_LONDON: {
         
         dt.hour = AsiaSession[ArraySize(AsiaSession) - 1] - 1;
         fromTime = StructToTime(dt);

         dt.hour = AsiaSession[0] - 1; // minus 1 to convert from utc+1 to utc
         toTime = StructToTime(dt);

         sessionParams.sessionCode = ASIA_SESSION;

         if(isDebug){
            Print("INSIDE GetPREVSESSPARAMS : CASE KILLZONE_LONDON ...");
            Print("FROM TIME: ", fromTime, " | To Time: ", toTime);
         }

      }
      break;

      case KILLZONE_NEWYORK: {
         
         dt.hour = LondonSession[ArraySize(LondonSession) - 1] - 1;
         fromTime = StructToTime(dt);

         dt.hour = LondonSession[0] - 1; // minus 1 to convert from utc+1 to utc
         toTime = StructToTime(dt);

         sessionParams.sessionCode = LONDON_SESSION;

         if(isDebug){
            Print("INSIDE GetPREVSESSPARAMS : CASE KILLZONE_NEWYORK ...");
            Print("FROM TIME: ", fromTime, " | To Time: ", toTime);
         }

      }
      
   }

   // get indices to feed to ihighest...
   searchStartIndex = iBarShift(_Symbol, wtf, fromTime);
   searchEndIndex = iBarShift(_Symbol, wtf, toTime);

   if(isDebug){
      Print("INSIDE GetPREVSESSPARAMS...");
      Print("Search Start Index: ", searchStartIndex, " | End Index: ", searchEndIndex);
   }


   sessionParams.sessionHigh = iHigh(_Symbol, wtf, iHighest(_Symbol, wtf, MODE_HIGH, MathAbs(searchEndIndex - searchStartIndex) + 1, searchStartIndex) );
   sessionParams.sessionLow = iLow(_Symbol, wtf, iLowest(_Symbol, wtf, MODE_LOW, MathAbs(searchEndIndex - searchStartIndex) + 1, searchStartIndex) );

   return sessionParams;
}


// checkLowestLow(now and AsianEndTime(not-inclusive)) : Low 




struct SweepData
{
   double high;
   double low;
   bool latestSweepIsLow;   
};


void checkSweepLevel(KILLZONECODE &killZone, SessionParams &prevSessionParams,SweepData &sweepData){

   int searchStartIndex;
   int searchEndIndex;

   ENUM_TIMEFRAMES wtf = mainTf;

   // Initialize anchor times
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);

   datetime fromTime = D'1990.12.16 06:00';
   datetime toTime = D'1990.12.16 06:00';

   switch (killZone)
   {
      case KILLZONE_LONDON: {
         fromTime = StructToTime(dt);

         dt.hour = AsiaSession[ArraySize(AsiaSession) - 1]; // minus 1 to convert from utc+1 to utc
         dt.min = 0;
         dt.sec = 0;
         toTime = StructToTime(dt);

         if(isDebug){
            Print("INSIDE checkSweepLevel : CASE KILLZONE_LONDON ...");
            Print("FROM TIME: ", fromTime, " | To Time: ", toTime);
         }

      }
      break;

      case KILLZONE_NEWYORK: {
         fromTime = StructToTime(dt);
         
         dt.hour = LondonSession[ArraySize(LondonSession) - 1]; // minus 1 to convert from utc+1 to utc
         dt.min = 0;
         dt.sec = 0;
         toTime = StructToTime(dt);

         if(isDebug){
            Print("INSIDE checkSweepLevel : CASE KILLZONE_NEWYOrk ...");
            Print("FROM TIME: ", fromTime, " | To Time: ", toTime);
         }

      }
      break;
   }

   // get indices to feed to ihighest...
   searchStartIndex = iBarShift(_Symbol, wtf, fromTime);
   searchEndIndex = iBarShift(_Symbol, wtf, toTime);

   if(isDebug){
      Print("INSIDE CheckSweepLevel...");
      Print("Search Start Index: ", searchStartIndex, " | End Index: ", searchEndIndex);
   }

   double priceNow = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_ASK), _Digits);
   double filter = 0.0003;

   if (priceNow > prevSessionParams.sessionHigh + filter){
      Print("High Sweep Detected");
      sweepData.high = NormalizeDouble(iHigh(_Symbol, wtf, iHighest(_Symbol, wtf, MODE_HIGH, MathAbs(searchEndIndex - searchStartIndex) + 1, searchStartIndex) ) , _Digits);
      sweepData.latestSweepIsLow = false;
   }

   if (priceNow < prevSessionParams.sessionLow + filter){
      Print("Low Sweep Detected");
      sweepData.low = NormalizeDouble(iLow(_Symbol, wtf, iLowest(_Symbol, wtf, MODE_LOW, MathAbs(searchEndIndex - searchStartIndex) + 1, searchStartIndex) ), _Digits);
      sweepData.latestSweepIsLow = true;
   }

   
   
}


// checkForBreakout(Bullish BO)
// - is bar 1 bullish? yes 
// - price > bar 1 high? yes return true

bool checkForBreakOut(bool isBullishBias){  // @ onTick

   double breakOutFilter = 0.0003;
   // double candleBodyFilter = 0.0002;
   // double breakOutFilter = 0.0;
   double candleBodyFilter = 0.0;

   double close = iClose(_Symbol, mainTf, 1);
   double open = iOpen(_Symbol, mainTf, 1);

   

   double price = isBullishBias ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   if(isBullishBias){
      Print("Checking for bullish BO, BreakPoint: ", breakPoint, " | Price: ", price);
      if (close >= (open + candleBodyFilter)) 
      {
         breakPoint = MathMin(iHigh(_Symbol, mainTf, 1), breakPoint);

         // breakPoint = MathMin(iHigh(_Symbol, mainTf, 1) : iLow(_Symbol, mainTf, 1), breakPoint);

         if (price > (breakPoint + breakOutFilter)){
            Print("Last Candle(1) is Bullish | BreakPoint + filter: ", (breakPoint + breakOutFilter));
            return true;
         }
       
      }
   }else {
      Print("Checking for bearish BO, Close: ", close, " | Price: ", price);
      if (close <= (open - candleBodyFilter)) {
         bearishBreakPt = MathMax(iLow(_Symbol, mainTf, 1), bearishBreakPt);

         if ( price < (bearishBreakPt - breakOutFilter)){
            Print("Last Candle(1) is Bearish | BreakPoint + filter: ", (bearishBreakPt - breakOutFilter));
            return true;
         }
         
      }
   }

   return false;
}



// SignalGen (TrendBias UPTREND, DOWNTREND) - only called in KillZones

void signalGen (SweepData &sweepData){

   double sweepFilter =  0.0002;

   bool isBullishBias = HourTrend.checkTrend() == 1 ? true : HourTrend.checkTrend() == -1 ? false : false;

   // bool isBullishBias = HourTrend.checkTrend() == 1 ? false : HourTrend.checkTrend() == -1 ? true : true;

   ShowTrendLabel(isBullishBias?1:-1);

   KILLZONECODE killZone = checkActiveKillZone();
   if(killZone == KILLZONE_UNKNOWN) return;

   

   if(isDebug){
   // LOG KILLZONE
   Print("ACTIVE KILLZONE: ", EnumToString(killZone));
   }

   SessionParams sessionParams = getPrevSessionParams(killZone);
   if(sessionParams.sessionCode == UNDEFINED_SESSION) return;

   if(isDebug){
   // LOG PREV Params
   Print("PREV SESSION: ", EnumToString(sessionParams.sessionCode), " HIGH: ",sessionParams.sessionHigh, " | LOW: ", sessionParams.sessionLow);
   }

   checkSweepLevel(killZone, sessionParams, sweepData);   

  
   // Print("SWEEP LEVEL: ", sweepLevel, isBullishBias ? "Prev Session LOW: " : "Prev Session HIGH: ", isBullishBias ? sessionParams.sessionLow : sessionParams.sessionHigh);
  

//    #UPTREND

   for(int i = 0; i < ArraySize(zonesProfitableToday); i++){
      
      if (zonesProfitableToday[i] == killZone) {
         Print("KILLZONE: ",killZone, " Already Profitable Today");
         return;
      } 
   }

   if (sweepData.low < sessionParams.sessionLow - sweepFilter && sweepData.latestSweepIsLow && PositionsTotal() <= 0 && isBullishBias){
      // buy with sweeplevel as sl
      if (checkForBreakOut(true)) {
         // Print("BUY @: ", NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_BID), _Digits), "SL @: ", sweepLevel);
         // placeOrder(true, sweepData.low - sweepFilter);
      }

   }
   
   else if (sweepData.high > sessionParams.sessionHigh + sweepFilter && !sweepData.latestSweepIsLow && PositionsTotal() <= 0 && !isBullishBias){
      // sell with sweeplevel as sl
      if (checkForBreakOut(false)){ 
         // Print("SELL @: ", NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_ASK), _Digits), "SL @: ", sweepLevel);
         // placeOrder(false, sweepData.high + sweepFilter);
      }
   }

   else {
      // no signal
      // Print("NO SIGNAL");
   }

}


void ShowTrendLabel(int trend)
{
   string label = "TrendLabel";
   // string label2 = "SignalLabel";
   string text = "";
   color clr = clrYellow;

   if (trend == 1) { text = "↑ Uptrend"; clr = clrLimeGreen; }
   if (trend == 0) {text = "<-> Neutral"; clr = clrYellow; }
   if (trend == -1) { text = "↓ Downtrend"; clr = clrRed; }

   if (ObjectFind(0, label) >= 0)
      ObjectDelete(0, label);

   ObjectCreate(0, label, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, label, OBJPROP_CORNER, CORNER_RIGHT_LOWER);
   ObjectSetInteger(0, label, OBJPROP_XDISTANCE, 250);
   ObjectSetInteger(0, label, OBJPROP_YDISTANCE, 70);
   ObjectSetInteger(0, label, OBJPROP_FONTSIZE, 12);
   ObjectSetInteger(0, label, OBJPROP_COLOR, clr);
   ObjectSetString(0, label, OBJPROP_TEXT, "Trend: " + text);
  
      
}




// @ 6% max DD | 10k - 3, 5k - 1.5, 2.5k - 0.75, 100k - 30  

double _lotSizeFixed = 0.4;
double _lotSizeTrailing = 0.6;
double _lotSizeAll = 3;  // @ 4% max DD | 10k - 2, 5k - 1, 2.5k - 0.5, 100k - 20  | (_lotSizeFixed + _lotSizeTrailing) * 2;
double maxRiskMargin = 0.0035;
double workingRiskMargin = 0.0020;
double profitMargin = 0.0030;




void placeOrder(bool isBuyOrder, double sl, StrategyConfig &sConfig){

   // posInfo.openHour = GetCurrentHour();

   // place limit
   int hours = 2;
   int minutes = 46;
   int seconds = 40;
   datetime expiryTime = TimeCurrent() + (hours * 3600) + (minutes * 60) + seconds;

   double gain = 0;
   int tpX = 2;
   
   if (isBuyOrder){

      Print("Placing Buy Order");

      double askPrice = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_ASK), _Digits);

      // if (MathAbs(bidPrice - sl) > maxRiskMargin) {
      //    Print("Too Much Risk for Buy");
      //    return;
      // }

      gain = MathAbs(askPrice - sl) * tpX;
      double tp = askPrice + gain;

      Print("EntryPrice: ", askPrice, "Stop: ", sl, "TakeProfit: ", tp);

      bool result;


      switch(sConfig.exitStrategy){
         case ExitStrategy::FIXED: {
            result = trade.Buy(
                        _lotSizeAll,    // lot size
                        _Symbol,    // symbol
                        askPrice,        // open price (market price)
                        sl,
                        tp,         // take profit
                        "Buy Order");//
                     }
         break;

         case ExitStrategy::TRAILING: {

            result = trade.Buy(
            _lotSizeAll,    // lot size
            _Symbol,    // symbol
            askPrice,        // open price (market price)
            sl,
            tp,         // take profit
            "Buy Order");//

         }
         break;

         case ExitStrategy::HYBRID: {

            result = trade.Buy(
            _lotSizeTrailing,    // lot size
            _Symbol,    // symbol
            askPrice,        // open price (market price)
            sl,
            tp,         // take profit
            "Buy Order");//

            result = trade.Buy(
               _lotSizeFixed,    // lot size
               _Symbol,    // symbol
               askPrice,        
               sl,
               tp,         // take profit
               "Buy Order");//

         }
         
         default: {

         }
      }

      
   }
   

   else {
      Print("Placing Sell Order");

      double bidPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);

      // if (MathAbs(askPrice - sl) > maxRiskMargin) {
      //    Print("Too Much Risk for Sell");
      //    return;
      // }

      gain = MathAbs(bidPrice - sl) * tpX;
      double tp = bidPrice - gain;


      bool result;

      switch(sConfig.exitStrategy){

         case ExitStrategy::FIXED: {
            result = trade.Sell(
                        _lotSizeAll,    // lot size
                        _Symbol,    // symbol
                        bidPrice,        // open price (market price)
                        sl,
                        tp,         // take profit
                        "Sell Order");//
                     }
         break;

         case ExitStrategy::TRAILING: {

            result = trade.Sell(
            _lotSizeAll,    // lot size
            _Symbol,    // symbol
            bidPrice,        // open price (market price)
            sl,
            tp,         // take profit
            "Sell Order");//

         }
         break;

         case ExitStrategy::HYBRID: {

            result = trade.Sell(
            _lotSizeTrailing,    // lot size
            _Symbol,    // symbol
            bidPrice,        // open price (market price)
            sl,
            tp,         // take profit
            "Sell Order");//

            result = trade.Sell(
               _lotSizeFixed,    // lot size
               _Symbol,    // symbol
               bidPrice,        // open price (market price)
               sl,
               tp,         // take profit
               "Sell Order");//

         }
         
         default: {

         }
      }


   }

}




void positionMonitor(StrategyConfig &sConfig)
{

   double beBuffer = 0.0000;

   for (int i = 0; i < PositionsTotal(); ++i)
   {
      // Print("Checking Position...");
      if (!PositionGetTicket(i)) continue;
      if (PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl        = PositionGetDouble(POSITION_SL);
      double tp        = PositionGetDouble(POSITION_TP);
      double positionSize = PositionGetDouble(POSITION_VOLUME);

      double priceNow  = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                                     : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      double gain = priceNow - openPrice;



      if (type == POSITION_TYPE_BUY && gain < 0) return;
      if (type == POSITION_TYPE_SELL && gain > 0) return;
      

      // Skip positions with no valid TP to base trailing logic on
      if (tp == 0) {
         continue;
      }

      // tp = NormalizeDouble( (type == POSITION_TYPE_BUY) ? openPrice + profitMargin : openPrice - profitMargin, _Digits);
      // tp = NormalizeDouble( (type == POSITION_TYPE_BUY) ? openPrice + (2 * MathAbs(sl - openPrice)) : openPrice - (2 * MathAbs(sl - openPrice)), _Digits);

      // ✅ Move SL to breakeven at 50% of original TP
      if ( (MathAbs(gain) > 0.6 * MathAbs(tp - openPrice)) && ((type == POSITION_TYPE_BUY && sl < openPrice) ||
      (type == POSITION_TYPE_SELL && sl > openPrice)) )
      {
         
         double newSl = (type == POSITION_TYPE_BUY)
            ? NormalizeDouble(openPrice + beBuffer, _Digits)
            : NormalizeDouble(openPrice - beBuffer, _Digits);

         // Print("Modified SL: ", newSl);

         if ((type == POSITION_TYPE_BUY && newSl > sl) ||
             (type == POSITION_TYPE_SELL && newSl < sl))
         {
            
            bool modified;

            switch (sConfig.exitStrategy)
            {
               case ExitStrategy::HYBRID:{
                  modified = trade.PositionModify(PositionGetInteger(POSITION_TICKET), newSl, positionSize == _lotSizeTrailing ? 0 : tp);
               }
               break;

               case ExitStrategy::TRAILING:{
                  modified = trade.PositionModify(PositionGetInteger(POSITION_TICKET), newSl, 0);
                  isBreakEvenTriggered = true;
               }
               break;

               case ExitStrategy::FIXED:{
                  modified = trade.PositionModify(PositionGetInteger(POSITION_TICKET), newSl, tp);
               }
           

            }


            
            
            if (!modified) {
               Print("Modify failed: ", trade.ResultRetcodeDescription());
            }else {
               Print("Moved SL to breakeven, set TP to 0.");
               SendNotification("Moved SL to breakeven, set TP to 2R.");
            }

            

         }
      }

   
   }

}






CDealInfo      m_deal;



void OnTradeTransaction(const MqlTradeTransaction& trans,
   const MqlTradeRequest& request,
   const MqlTradeResult& result)
{

Print("ON TRADE TRANSACTION CALLED...");
//--- get transaction type as enumeration value
ENUM_TRADE_TRANSACTION_TYPE type=trans.type;
//--- if transaction is result of addition of the transaction in history
if(type==TRADE_TRANSACTION_DEAL_ADD)
{
if(HistoryDealSelect(trans.deal))
m_deal.Ticket(trans.deal);
else
{
Print(__FILE__," ",__FUNCTION__,", ERROR: HistoryDealSelect(",trans.deal,")");
return;
}
//---
long reason=-1;
if(!m_deal.InfoInteger(DEAL_REASON,reason))
{
Print(__FILE__," ",__FUNCTION__,", ERROR: InfoInteger(DEAL_REASON,reason)");
return;
}
if ((ENUM_DEAL_REASON)reason == DEAL_REASON_SL)
{
   long dealType;
   if (!m_deal.InfoInteger(DEAL_TYPE, dealType))
   {
      Print("ERROR: Failed to get DEAL_TYPE");
      return;
   }

   string positionSide = (dealType == DEAL_TYPE_SELL) ? "BUY" : "SELL";

   Print("Stop Loss hit for a ", positionSide, " position!");

   // Do your SL logic
   Alert("Stop Loss activation for a " + positionSide + " position");
   // minorTrend = positionSide == "BUY" ? -1 : 1;
   // Print("Minor trend updated to : ", minorTrend);
   

   // onStopLossTriggered(positionSide == "BUY" ? false : true); // an exit by BUY means position was a sell/short not a buy/long
   
   // minorTrend = 0;
   // tradeSignal = 0;
}

else
if((ENUM_DEAL_REASON)reason==DEAL_REASON_TP){

   zonesProfitableToday[todaysTpCnt++] = checkActiveKillZone();
   Print("Today's TP cnt: ", todaysTpCnt, " | Profitable KillZone: ", EnumToString(checkActiveKillZone()));
   Alert("Take Profit activation");
}

}
}

bool isMomentumLow(ENUM_POSITION_TYPE posType, double&emaArr[]){
   Print("EMA 5 (1) vs (0): EMA5 2= ", emaArr[1], "| EMA5 1= ", emaArr[0]);
   return posType == POSITION_TYPE_BUY ? emaArr[1] > emaArr[0] : emaArr[1] < emaArr[0];
}

struct EntryDataToValidate{
   bool isBuyOrder;
   double emaFastVal;
   double emaMidVal;
   double emaSlowVal;
   double dayEmaFastVal;
   double dayEmaMidVal;
   double dayEmaSlowVal;
   double atrThreshold;
   double emaFastArr[14];

   EntryDataToValidate(bool _isBuyOrder, double _emaFastVal, double _emaMidVal, double _emaSlowVal, 
                       double _dayEmaFastVal, double _dayEmaMidVal, double _dayEmaSlowVal, double _atrThreshold,
                      double &_emaFastArr[]){
      isBuyOrder = _isBuyOrder;
      emaFastVal = _emaFastVal;
      emaMidVal = _emaMidVal;
      emaSlowVal = _emaSlowVal;
      dayEmaFastVal = _dayEmaFastVal;
      dayEmaMidVal = _dayEmaMidVal;
      dayEmaSlowVal = _dayEmaSlowVal;

      atrThreshold = _atrThreshold;
     
      for(int i = 0; i < ArraySize(_emaFastArr); i++){
         emaFastArr[i] = _emaFastArr[i];
      }
   }
};


bool validateEntry(EntryDataToValidate &entryData, StrategyConfig &sConfig){

   // Check KillZones 
   if(sConfig.checkKillZone){
      KILLZONECODE killZone = checkActiveKillZone();
      int arrSize = ArraySize(sConfig.invalidKz);

      for(int i = 0; i < arrSize; i++){
         if(killZone == sConfig.invalidKz[i]) {
            Print("SIGNAL INVALID: Signal Fired Outside Valid KillZones!");
            return false;
         }
      }
   }

   // Check EmaGap and Arrangements
   if(sConfig.checkEmaGap){

      if(MathAbs(entryData.emaFastVal - entryData.emaMidVal) < (entryData.atrThreshold * 0.25)) {
         Print("SIGNAL INVALID: Main Ema5 less Ema9 is less than threshold!");
         return false;
      }

   }

   // check EmaFast Momentum
   if(sConfig.checkEmaMomentum){
      ENUM_POSITION_TYPE pType = entryData.isBuyOrder ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
         if(isMomentumLow(pType, entryData.emaFastArr)) {
               Print("SIGNAL INVALID: Main Ema5 momentum is too low!");
               return false;
            }
   }
   

   // checkDayEmaFastvsMidvsSlow
   if(sConfig.checkDayEmaFastvsSlow){
      bool dayEmaCheck = entryData.isBuyOrder 
                      ? entryData.dayEmaFastVal > entryData.dayEmaMidVal && entryData.dayEmaMidVal > entryData.dayEmaSlowVal  
                      : entryData.dayEmaFastVal < entryData.dayEmaMidVal && entryData.dayEmaMidVal < entryData.dayEmaSlowVal ;
      if(!dayEmaCheck){
         Print("SIGNAL INVALID: Bias Ema5 vs Ema9 vs Ema50 Alignment Check Failed!");
          return false;
         }

      bool emaArrangementCheck = entryData.isBuyOrder
                           ? entryData.emaFastVal > entryData.emaMidVal && entryData.emaFastVal < entryData.emaSlowVal
                           : entryData.emaFastVal < entryData.emaMidVal && entryData.emaFastVal > entryData.emaSlowVal;

      if(!emaArrangementCheck){
         Print("SIGNAL INVALID: Main Ema Arrangements Check Failed!");
          return false;
         }

   }
   


   return true;
}

// Returns Index of Most Recent Peak or Dip, Returns -1 if none found within bounds order * 16
int searchForPeakOrDip(bool isBuyOrder, ENUM_TIMEFRAMES tf, int order = 1){

   int s = order + 1; // start index

   
   
   while(s < (order * 16)){ // max lookback period in bars
      bool foundPeakOrDip = isBuyOrder
                           ? iLow(_Symbol, tf, s) < iLow(_Symbol, tf, s+order) && iLow(_Symbol, tf, s) < iLow(_Symbol, tf, s-order) 
                           : iHigh(_Symbol, tf, s) > iHigh(_Symbol, tf, s+order) && iHigh(_Symbol, tf, s) > iHigh(_Symbol, tf, s-order);
      
      if(foundPeakOrDip) return s;
      else s++;

   }          

   return -1;
}


double getStopPrice(bool isBuyOrder, ENUM_TIMEFRAMES tf, double atrValue){

   double noiseFilter = atrValue * 0.2;
   double maxRisk = atrValue * 2;

   int peakOrDipIdx = searchForPeakOrDip(isBuyOrder, tf); 

   double peakOrDipPrice = isBuyOrder 
                     ? NormalizeDouble(iLow(_Symbol, tf, peakOrDipIdx), _Digits) - noiseFilter
                     : NormalizeDouble(iHigh(_Symbol, tf, peakOrDipIdx), _Digits) + noiseFilter;

   Print("PeakOrDip Index: ", peakOrDipIdx, "Price: ", peakOrDipPrice);   


   double openPrice = isBuyOrder 
                     ? NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_BID), _Digits) 
                     : NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_ASK), _Digits);               

   double risk = isBuyOrder ? openPrice - peakOrDipPrice : openPrice + peakOrDipPrice;



   return peakOrDipPrice; // return calculated and safe sl
}