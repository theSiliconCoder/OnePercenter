

class MoniePilot
{
private:
  /* data */
public:
  class Indicators {

    public:
      class SuperTrend{

        private:
          ENUM_TIMEFRAMES timeFrame;
          int superTrendPeriod;
          double superTrendMult;
          double superVals[];
          int superHandler;

        public:
          enum TREND {
            DOWN, UP
          };

          SuperTrend(ENUM_TIMEFRAMES _timeFrame = PERIOD_H4, int trendPeriod = 14, double trendMultiplier = 3.0) // typical: period = 14, multiplier = 3.0
            : timeFrame(_timeFrame), superTrendPeriod(trendPeriod), superTrendMult(trendMultiplier)
          {
            ArraySetAsSeries(superVals, true);
            superHandler = iCustom(_Symbol, timeFrame, "Supertrend", superTrendPeriod, superTrendMult);
          }

          int checkTrend(int indx = 2) 
          {
            CopyBuffer(superHandler,0,0,14,superVals);
            double cndlOpenH4 = iOpen(_Symbol,timeFrame,0); // get open of current bar
            
            return cndlOpenH4 > superVals[indx] ? 1 : -1; // compare open of current bar with current value of supertrend
          }

          double getVal(int arrIndex = 0) { return superVals[arrIndex]; }       

      };

      class ATR {
        private:
          ENUM_TIMEFRAMES timeFrame;
          int atrRange;
          double atrVals[];
          int atrHandler;

        public:
          ATR(ENUM_TIMEFRAMES _timeFrame = PERIOD_H4, int _atrRange = 14)
          : atrRange(_atrRange), timeFrame(_timeFrame)
          {
            atrHandler = iATR(NULL,timeFrame,atrRange);
          }

          double getAtrVal(int arrIndex = 0){
               
            CopyBuffer(atrHandler,0,0,5,atrVals); // more clarity

            return NormalizeDouble(atrVals[arrIndex], 5);
          }


      };
  };
  
  class Contexts {

    public:

      class waitForBreakOutContext {
        public:
          // static int contextCnt;
          bool   prematureBreakout;
          int    startPos;
          int    barsCnt;
          double maxHighVal;
          int maxHighPos;
          double dip;
          double mostRecentLow;
          double newHigh;
          double cndlOpen;


          waitForBreakOutContext(){
            prematureBreakout = NULL;
            startPos = INT_MAX;
            maxHighVal = INT_MIN;
            dip = 0;
            mostRecentLow = NULL;
            newHigh = NULL;
            barsCnt = 0;
            
          }


      }; 

      class find_12345_Pattern {
        public:          
          int     firstPeakIndex;
          // double firstPeakVal;
          int     secondPeakIndex;
          // double secondPeakVal;
          int     firstDipIndex;
          int     secondDipIndex;
          int     barsCnt;
          short   progress;
          int     dipIndex;
          double  recommendedEntryPrice;
          double  lastDipPrice;
          double  secondPeakPrice;
          double  lastPeakB4Entry;
          int     lookBack;
          int     decimalPlaces;
          short     maxProgress;

          find_12345_Pattern(){
            progress = 0; // track pattern progress 0 to 5
            maxProgress = 3;
            firstPeakIndex = -1;
            secondPeakIndex = -1;
            firstDipIndex = -1;
            secondDipIndex = -1;
            barsCnt = 0;
            lookBack = 7;
            decimalPlaces = 5;
            lastDipPrice = 0;
            recommendedEntryPrice = 0;
            secondPeakPrice = 0;
            lastPeakB4Entry = INT_MAX;

          }

          void resetContext(){
            progress = 0;
            firstPeakIndex = -1;
            secondPeakIndex = -1;
            firstDipIndex = -1;
            secondDipIndex = -1;
            barsCnt = 0;
            lookBack = 7;
            decimalPlaces = 5;
            dipIndex = -1;
            lastDipPrice = 0;
            // lastPeakB4Entry = INT_MAX;
            // recommendedEntryPrice = 0;
            secondPeakPrice = 0;

            
          }



      }; 

  };
  
  

  

};

