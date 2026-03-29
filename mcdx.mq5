//+------------------------------------------------------------------+
//|                                           SmartMCDX_TopGreen.mq5 |
//+------------------------------------------------------------------+
#property indicator_separate_window
#property indicator_buffers 4
#property indicator_plots   4

// Thứ tự vẽ: Xanh (dưới cùng) -> Vàng -> Đỏ (trên cùng)
#property indicator_type1   DRAW_HISTOGRAM
#property indicator_color1   clrLimeGreen // Retailer
#property indicator_width1   2

#property indicator_type2   DRAW_HISTOGRAM
#property indicator_color2   clrYellow    // Hot Money
#property indicator_width2   2

#property indicator_type3   DRAW_HISTOGRAM
#property indicator_color3   clrRed       // Banker
#property indicator_width3   2

#property indicator_type4   DRAW_LINE
#property indicator_color4   clrDeepSkyBlue // Blue Line
#property indicator_width4   2

// Thông số giống hệt TradingView của bạn
input int    InpRSIPeriod   = 50;  
input int    InpMAPeriod    = 50;  
input double InpSensitivity = 1.5; 

double BufR[], BufH[], BufB[], BufMA[];
int hRSI;

int OnInit() {
   SetIndexBuffer(0, BufR, INDICATOR_DATA);
   SetIndexBuffer(1, BufH, INDICATOR_DATA);
   SetIndexBuffer(2, BufB, INDICATOR_DATA);
   SetIndexBuffer(3, BufMA, INDICATOR_DATA);
   hRSI = iRSI(_Symbol, _Period, InpRSIPeriod, PRICE_CLOSE);
   return(INIT_SUCCEEDED);
}

int OnCalculate(const int rates_total, const int prev_calculated, const datetime &time[],
                const double &open[], const double &high[], const double &low[],
                const double &close[], const long &tick_volume[], const long &volume[], const int &spread[]) 
{
   double rsi[];
   ArraySetAsSeries(rsi, true);
   if(CopyBuffer(hRSI, 0, 0, rates_total, rsi) <= 0) return(0);

   int start = (prev_calculated > 0) ? prev_calculated - 1 : 0;

   for(int i = start; i < rates_total; i++) {
      double val = rsi[rates_total - 1 - i];
      
      // LOGIC MỚI ĐỂ HIỆN MÀU XANH LÁ PHÍA TRÊN:
      // 1. Banker (Đỏ): Chỉ mạnh khi RSI > 50
      double b = (val - 50) * InpSensitivity;
      BufB[i] = MathMax(0, MathMin(20, b));
      
      // 2. Hot Money (Vàng): Tính theo tỷ lệ để KHÔNG chạm mức 20 quá sớm
      // Chúng ta dùng hệ số thấp hơn một chút hoặc threshold khác
      double h = (val - 35) * (InpSensitivity * 0.8) + 5; 
      BufH[i] = MathMax(0, MathMin(18.5, h)); // Khống chế ở mức 18.5 để luôn hở màu xanh
      
      // 3. Retailer (Xanh lá): Luôn là mức trần 20
      BufR[i] = 20.0;

      // Đảm bảo Đỏ không cao hơn Vàng để tránh lỗi hiển thị
      if(BufB[i] > BufH[i]) BufH[i] = BufB[i];
   }

   // Tính đường EMA 50 cho Banker (Đường màu xanh dương)
   double pr = 2.0 / (InpMAPeriod + 1.0);
   for(int i = start; i < rates_total; i++) {
      if(i == 0) BufMA[i] = BufB[i];
      else BufMA[i] = BufB[i] * pr + BufMA[i-1] * (1.0 - pr);
   }

   return(rates_total);
}