//+------------------------------------------------------------------+
//|                                                     DipBuyer.mq5 |
//|                          Copyright 2024, theSiliconCoder |
//|                                                                |
//+------------------------------------------------------------------+

// DipBuyer assumes you deploy it during in an uptrend on a 4H chart

#property copyright "Copyright 2024, theSiliconCoder."
#property link      "https://mql5.com"
#property version   "1.00"
//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
#include <trade/trade.mqh>

double lotSize = 4;
double candleArr[];
int handler;
int lookBack = 5;

double TpPoints = 1200;
double SlPoints = 200;
double NewHighPoints = 400;
double NewLowPoints = 200;

int Magic = 1;

int Trailn_TrigPts = 0.8 * TpPoints; // put trigger as close to TpPoints
int Trailn_TPPts = 1000;
int Trailn_SLPts = 400;

int barsTotal;

int maxHiCndl, minLoCndl, newHiCndl, newLoCndl;
double maxHigh=0, minLow=0, entryPrice=0;

bool dipBuyerInit = false;
bool uptrend = false;

CTrade trade;


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void runDipBuyer()
  {
  
   

   if(!dipBuyerInit)
      initDipBuyer();

   else{
      //positionMonitor();
      monitorChart();
      }

  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void initDipBuyer()
  {
   dipBuyerInit = true;

   ArraySetAsSeries(candleArr, true);
   barsTotal = Bars(_Symbol,PERIOD_H4);


// initial dip-buy attempt
   maxHiCndl = iHighest(_Symbol, PERIOD_H4, MODE_HIGH, lookBack);
   minLoCndl = iLowest(_Symbol, PERIOD_H4, MODE_LOW, lookBack);

   maxHigh = iHigh(_Symbol, PERIOD_H4, maxHiCndl);
   minLow = iLow(_Symbol, PERIOD_H4, minLoCndl);

  }


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void monitorChart()
  {
   int bars = Bars(_Symbol, PERIOD_H4);

   Comment("\nOrders: ", OrdersTotal(),"\n",
           "\nPositions: ", PositionsTotal(),"\n",
           "\nUpdated maxHigh: ", maxHigh,"\n",
           "\nUpdated minLow: ", minLow,"\n"

          );

// on each new bar, monitor chart for breakout
   if(barsTotal != bars)
     {

      barsTotal = bars; // update barsTotal with newly drawn bar/candle

      newHiCndl = iHighest(_Symbol, PERIOD_H4, MODE_HIGH, lookBack,0);
      double newHigh = iHigh(_Symbol, PERIOD_H4, newHiCndl);

      newLoCndl = iLowest(_Symbol, PERIOD_H4, MODE_LOW, lookBack,0);
      double newLow = iLow(_Symbol, PERIOD_H4, newLoCndl);

      if(newHigh > ((NewHighPoints * _Point) + maxHigh))  // if fresh breakout aka new all time high within lookBack range
        {
         double temp = maxHigh;
         maxHigh = newHigh;

         //Comment("\nUpdating maxHigh: ", maxHigh,"\n",
         //        "\nPrev maxHigh: ", temp);



         minLoCndl = iLowest(_Symbol, PERIOD_H4, MODE_LOW, lookBack);
         minLow = iLow(_Symbol, PERIOD_H4, minLoCndl);

         // if the order is still pending, update order based on new price
         if(OrdersTotal() > 0)
           {
            entryPrice = maxHigh - ((maxHigh - minLow) * 0.5);
            executeBuyLimit(entryPrice, minLow, maxHigh, true);
           }

         else
            if(OrdersTotal() == 0 && uptrend)
              {
               entryPrice = maxHigh - ((maxHigh - minLow) * 0.5);
               executeBuyLimit(entryPrice, minLow, maxHigh, false);
              }

            else
               if(OrdersTotal() == 0 && PositionsTotal()==0)
                 {
                  // look for opportunity to place new order: dipBuyerInit = false;
                  // barsSinceLastAttempt++;
                  // if (barsSinceLastAttempt >= 5)
                  dipBuyerInit = false; // redeploy dipBuyer algo

                 }


        }


      else
         if(newLow < (minLow - (NewLowPoints * _Point)))   // detected a new all time low within lookBack range, means market turned agains our position
           {
            //positionMonitor(NULL, NULL, NULL, true);
            dipBuyerInit = false; // redeploy dipBuyer algo so that maxHigh etc can be recalibrated
           }


     }


  }


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void executeBuyLimit(double price, double sl, double tp, bool update)
  {

   if(OrdersTotal() == 0 && PositionsTotal()==0)
     {
      trade.BuyLimit(lotSize, price, _Symbol, sl - (SlPoints * _Point), tp + (TpPoints * _Point));
     }

   if(update)    // update order based on chart changes
     {


      for(int i = 0; i < OrdersTotal(); ++i)
        {
         ulong currOrder = OrderGetTicket(i);

         trade.OrderModify(currOrder,price, sl - (SlPoints * _Point),tp + (TpPoints * _Point),ORDER_TIME_GTC,0);
        }

     }

  }


  bool isValidOrder(ENUM_ORDER_TYPE orderType, double orderPrice){

    for (int i = 0; i < OrdersTotal(); ++i){
      ulong ticket = OrderGetTicket(i);
  
      if ( OrderGetInteger(ORDER_TYPE) == orderType || OrderGetDouble(ORDER_PRICE_OPEN) == orderPrice) 
      {
        Print("Duplicate order found. Ticket: ", ticket);
        return false;
      } 
    }

    return true;
  }



bool isUniqueOrder(ENUM_ORDER_TYPE orderType, double orderPrice){

 for (int i = 0; i < OrdersTotal(); ++i)
   {
    ulong currOrder = OrderGetTicket(i);

      // Select the ith order from the pool
      if (OrderSelect(currOrder))
      {
         // Only compare pending orders of the same type
         ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
         double openPrice = OrderGetDouble(ORDER_PRICE_OPEN);
         ulong ticket = OrderGetInteger(ORDER_TICKET);

         // Check for same type and price (rounded to 1 pip precision)
         if (type == orderType && NormalizeDouble(openPrice, _Digits) == NormalizeDouble(orderPrice, _Digits))
         {
            Print("Duplicate order found. Ticket: ", ticket);
            return false;
         }
      }
   }
   return true; // No matching order found
}




//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void closeAllOrdersandPositions()
  {
   
   for (int i = 0; i <= OrdersTotal(); ++i)
     {
      ulong currOrder = OrderGetTicket(i);

      trade.OrderDelete(currOrder);
     }


   for (int i = 0; i <= PositionsTotal(); ++i)
     {

      ulong currPos = PositionGetTicket(i);

         trade.PositionClose(currPos); // close position

     }
  }


  void closeAllOrders(ENUM_ORDER_TYPE orderType)
  {
   
    for (int i = 0; i <= OrdersTotal(); ++i)
    {
      ulong currOrder = OrderGetTicket(i);

      if(OrderGetInteger(ORDER_TYPE) == orderType){
          trade.OrderDelete(currOrder);
      }
    
    }

  }

  void closeAllPositions(ENUM_POSITION_TYPE positionType)
  {
   
    for (int i = 0; i <= PositionsTotal(); ++i)
    {
      ulong currPosition = PositionGetTicket(i);

      if(PositionGetInteger(POSITION_TYPE) == positionType){
          trade.PositionClose(currPosition);
      }
    
    }

  }