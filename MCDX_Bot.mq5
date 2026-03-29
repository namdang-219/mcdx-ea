//+------------------------------------------------------------------+
//|                                                     MCDX_Bot.mq5 |
//|                                                   Antigravity AI |
//+------------------------------------------------------------------+
#property copyright "Antigravity AI"
#property link      ""
#property version   "1.00"

#include <Trade\Trade.mqh>

input double InpLotSize = 0.1;               // Lot Size
input int    InpTakeProfit = 500;            // Take Profit (points)
input int    InpStopLoss = 500;              // Stop Loss (points)
input int    InpTrailingStop = 200;          // Trailing Stop (points)
input int    InpTrailingStep = 50;           // Trailing Step (points)
input double InpMinBankerFilter = 5.0;       // Min Red Column (Banker) Buy Filter
input int    InpConfirmCandles = 3;          // Entry Delay (candles after cross)

input string dummy1 = "--- MCDX Indicator ---"; // MCDX Settings
input int    InpRSIPeriod   = 50;            // MCDX: RSI Period
input int    InpMAPeriod    = 50;            // MCDX: MA Period
input double InpSensitivity = 1.5;           // MCDX: Sensitivity
input ulong  InpMagicNumber = 123456;        // Magic Number

CTrade trade;
int handle_m1;
int handle_m5;
datetime last_bar_m1 = 0;

//+------------------------------------------------------------------+
//| Initialization function                                          |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   
   // Load indicator: Make sure "mcdx.ex5" or "mcdx.mq5" is placed correctly (e.g. same folder or Indicators folder)
   handle_m1 = iCustom(_Symbol, PERIOD_M1, "mcdx", InpRSIPeriod, InpMAPeriod, InpSensitivity);
   handle_m5 = iCustom(_Symbol, PERIOD_M5, "mcdx", InpRSIPeriod, InpMAPeriod, InpSensitivity);
   
   if(handle_m1 == INVALID_HANDLE || handle_m5 == INVALID_HANDLE)
   {
      Print("Failed to load MCDX indicator. Ensure mcdx.ex5 is accessible in MQL5/Indicators or the local folder.");
      return(INIT_FAILED);
   }
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Deinitialization function                                        |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(handle_m1 != INVALID_HANDLE) IndicatorRelease(handle_m1);
   if(handle_m5 != INVALID_HANDLE) IndicatorRelease(handle_m5);
   
   ObjectsDeleteAll(0, -1, OBJ_ARROW_BUY);
   ObjectsDeleteAll(0, -1, OBJ_ARROW_SELL);
   ObjectsDeleteAll(0, -1, OBJ_ARROW_CHECK);
   ObjectsDeleteAll(0, -1, OBJ_ARROW_STOP);
}

//+------------------------------------------------------------------+
//| Helper to draw chart markers                                     |
//+------------------------------------------------------------------+
void DrawMarker(string name, ENUM_OBJECT type, datetime time, double price, color clr)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, type, 0, time, price);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
   }
}

//+------------------------------------------------------------------+
//| Process open positions (Trailing Stops)                          |
//+------------------------------------------------------------------+
void ProcessTrailingStops()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
      {
         int type = (int)PositionGetInteger(POSITION_TYPE);
         double pos_open = PositionGetDouble(POSITION_PRICE_OPEN);
         double pos_sl = PositionGetDouble(POSITION_SL);
         
         if(type == POSITION_TYPE_BUY)
         {
            if(InpTrailingStop > 0)
            {
               double new_sl = SymbolInfoDouble(_Symbol, SYMBOL_BID) - InpTrailingStop * _Point;
               new_sl = NormalizeDouble(new_sl, _Digits);
               if(new_sl > pos_open && (pos_sl == 0 || new_sl - pos_sl >= InpTrailingStep * _Point))
               {
                  trade.PositionModify(ticket, new_sl, PositionGetDouble(POSITION_TP));
               }
            }
         }
         else if(type == POSITION_TYPE_SELL)
         {
            if(InpTrailingStop > 0)
            {
               double new_sl = SymbolInfoDouble(_Symbol, SYMBOL_ASK) + InpTrailingStop * _Point;
               new_sl = NormalizeDouble(new_sl, _Digits);
               if(new_sl < pos_open && (pos_sl == 0 || pos_sl - new_sl >= InpTrailingStep * _Point))
               {
                  trade.PositionModify(ticket, new_sl, PositionGetDouble(POSITION_TP));
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Tick function                                                    |
//+------------------------------------------------------------------+
void OnTick()
{
   // 1. Always evaluate trailing stops per tick
   ProcessTrailingStops();
   
   // 2. Evaluate signals exactly once per M1 bar
   datetime current_bar_time = (datetime)SeriesInfoInteger(_Symbol, PERIOD_M1, SERIES_LASTBAR_DATE);
   if(last_bar_m1 == 0) last_bar_m1 = current_bar_time; 
   bool is_new_bar_m1 = (current_bar_time != last_bar_m1);
   
   if(is_new_bar_m1)
   {
      last_bar_m1 = current_bar_time;
      
      double m1_banker[], m1_blue[], m5_banker[], m5_blue[];
      ArraySetAsSeries(m1_banker, true);
      ArraySetAsSeries(m1_blue, true);
      ArraySetAsSeries(m5_banker, true);
      ArraySetAsSeries(m5_blue, true);
      
      if(CopyBuffer(handle_m5, 2, 0, 2, m5_banker) <= 0) return;
      if(CopyBuffer(handle_m5, 3, 0, 2, m5_blue) <= 0) return;
      if(CopyBuffer(handle_m1, 2, 0, InpConfirmCandles + 2, m1_banker) <= 0) return;
      if(CopyBuffer(handle_m1, 3, 0, InpConfirmCandles + 2, m1_blue) <= 0) return;
      
      static bool has_bought_this_wave = false;
      static bool has_sold_this_wave = false;
      
      // Reset wave trackers if the M1 trend definitively breaks
      if(m1_blue[1] >= m1_banker[1]) has_bought_this_wave = false;
      if(m1_blue[1] <= m1_banker[1]) has_sold_this_wave = false;
      
      int openBuys = 0;
      int openSells = 0;
      
      // -- Check Exit Conditions --
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
         {
            int type = (int)PositionGetInteger(POSITION_TYPE);
            
            if(type == POSITION_TYPE_BUY)
            {
               openBuys++;
               // Close Buy: m1_blue goes above m1_banker
               if(m1_blue[1] > m1_banker[1] && m1_blue[2] <= m1_banker[2]) 
               {
                  double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
                  DrawMarker("CloseBuy_" + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES|TIME_SECONDS), OBJ_ARROW_CHECK, TimeCurrent(), bid, clrOrange);
                  
                  if(trade.PositionClose(ticket))
                  {
                     openBuys--; 
                  }
               }
            }
            else if(type == POSITION_TYPE_SELL)
            {
               openSells++;
               // Close Sell: m1_blue goes below m1_banker OR m1_blue goes to near 0
               if((m1_blue[1] < m1_banker[1] && m1_blue[2] >= m1_banker[2]) || m1_blue[1] <= 0.001)
               {
                  double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
                  DrawMarker("CloseSell_" + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES|TIME_SECONDS), OBJ_ARROW_STOP, TimeCurrent(), ask, clrAqua);
                  
                  if(trade.PositionClose(ticket))
                  {
                     openSells--;
                  }
               }
            }
         }
      }
      
      // -- Check Entry Conditions --
      bool m5_uptrend = m5_blue[1] < m5_banker[1];
      bool m5_downtrend = m5_blue[1] > m5_banker[1];
      
      bool m1_buy_confirmed = true;
      bool m1_sell_confirmed = true;
      
      // Ensure the trend has been sustained for InpConfirmCandles
      for(int k = 1; k <= InpConfirmCandles; k++)
      {
         if(m1_blue[k] >= m1_banker[k]) m1_buy_confirmed = false;
         if(m1_blue[k] <= m1_banker[k]) m1_sell_confirmed = false;
      }
      
      // Buy Signal
      if(openBuys == 0 && !has_bought_this_wave && m5_uptrend && m1_buy_confirmed && m1_banker[1] >= InpMinBankerFilter)
      {
         has_bought_this_wave = true;
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         DrawMarker("Buy_" + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES|TIME_SECONDS), OBJ_ARROW_BUY, TimeCurrent(), ask - 5 * _Point, clrLimeGreen);
         ObjectCreate(0, "VLineBuy_" + TimeToString(TimeCurrent()), OBJ_VLINE, 0, TimeCurrent(), 0);
         ObjectSetInteger(0, "VLineBuy_" + TimeToString(TimeCurrent()), OBJPROP_COLOR, clrLimeGreen);
         
         double sl = InpStopLoss > 0 ? NormalizeDouble(ask - InpStopLoss * _Point, _Digits) : 0;
         double tp = InpTakeProfit > 0 ? NormalizeDouble(ask + InpTakeProfit * _Point, _Digits) : 0;
         
         if(!trade.Buy(InpLotSize, _Symbol, ask, sl, tp))
         {
            Print("Buy failed: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
         }
      }
      
      // Sell Signal
      if(openSells == 0 && !has_sold_this_wave && m5_downtrend && m1_sell_confirmed)
      {
         has_sold_this_wave = true;
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         DrawMarker("Sell_" + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES|TIME_SECONDS), OBJ_ARROW_SELL, TimeCurrent(), bid + 5 * _Point, clrCrimson);
         ObjectCreate(0, "VLineSell_" + TimeToString(TimeCurrent()), OBJ_VLINE, 0, TimeCurrent(), 0);
         ObjectSetInteger(0, "VLineSell_" + TimeToString(TimeCurrent()), OBJPROP_COLOR, clrCrimson);
         
         double sl = InpStopLoss > 0 ? NormalizeDouble(bid + InpStopLoss * _Point, _Digits) : 0;
         double tp = InpTakeProfit > 0 ? NormalizeDouble(bid - InpTakeProfit * _Point, _Digits) : 0;
         
         if(!trade.Sell(InpLotSize, _Symbol, bid, sl, tp))
         {
            Print("Sell failed: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
         }
      }
   }
}
//+------------------------------------------------------------------+
