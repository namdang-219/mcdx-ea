//+------------------------------------------------------------------+
//|                                     MCDX_PRO_VERSION.mq5         |
//+------------------------------------------------------------------+
#property strict
#include <Trade\Trade.mqh>

input double   InpLots           = 0.1;
input int      InpTP_Pips        = 10;
input int      InpVirtualSL_Pips = 20;
input int      InpTrailingStart  = 3;
input int      InpTrailingStop   = 2;
input string   InpIndicatorName  = "MCDX"; 

// Theo ảnh của bạn: Số thứ 3 là Đỏ, Số thứ 4 là Xanh
input int      InpRedBuffer      = 2;  
input int      InpBlueBuffer     = 3;  
input long     InpMagic          = 123456;

CTrade         trade;
int            handleMCDX;
double         vSL = 0;
datetime       lastBarTime; // Biến chặn vào lệnh liên tục

int OnInit() {
    handleMCDX = iCustom(_Symbol, _Period, InpIndicatorName);
    if(handleMCDX == INVALID_HANDLE) return(INIT_FAILED);
    trade.SetExpertMagicNumber(InpMagic);
    return(INIT_SUCCEEDED);
}

void OnTick() {
    double red[], blue[];
    ArraySetAsSeries(red, true);
    ArraySetAsSeries(blue, true);

    if(CopyBuffer(handleMCDX, InpRedBuffer, 0, 1, red) < 0 || 
       CopyBuffer(handleMCDX, InpBlueBuffer, 0, 1, blue) < 0) return;

    double valRed  = red[0];
    double valBlue = blue[0];
    
    // Hiển thị trạng thái lên màn hình
    string status = (valBlue < valRed) ? "ĐANG ƯU TIÊN BUY" : "ĐANG ƯU TIÊN SELL";
    Comment("--- BOT MCDX KỶ LUẬT ---\n",
            "RED: ", DoubleToString(valRed, 2), "\n",
            "BLUE: ", DoubleToString(valBlue, 2), "\n",
            "TRẠNG THÁI: ", status);

    bool hasPos = PositionSelectByMagic(_Symbol, InpMagic);

    // LOGIC VÀO LỆNH (Chỉ vào khi nến mới xuất hiện và chưa có lệnh)
    if(!hasPos && lastBarTime != iTime(_Symbol, _Period, 0)) {
        
        // ĐÚNG Ý BẠN: Xanh dương DƯỚI màu đỏ (Blue < Red) -> BUY
        if(valBlue < valRed && valRed > 0) {
            double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            if(trade.Buy(InpLots, _Symbol, price, 0, 0)) {
                vSL = price - (InpVirtualSL_Pips * _Point * 10);
                lastBarTime = iTime(_Symbol, _Period, 0); // Đánh dấu đã vào lệnh ở nến này
            }
        }
        // NGƯỢC LẠI: Xanh dương TRÊN màu đỏ (Blue > Red) -> SELL
        else if(valBlue > valRed && valRed > 0) {
            double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            if(trade.Sell(InpLots, _Symbol, price, 0, 0)) {
                vSL = price + (InpVirtualSL_Pips * _Point * 10);
                lastBarTime = iTime(_Symbol, _Period, 0); // Đánh dấu đã vào lệnh ở nến này
            }
        }
    }
    
    if(hasPos) ManagePosition();
}

void ManagePosition() {
    if(!PositionSelectByMagic(_Symbol, InpMagic)) return;
    double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
    double curBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double curAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    long type = PositionGetInteger(POSITION_TYPE);
    
    if(type == POSITION_TYPE_BUY) {
        double pips = (curBid - openPrice) / (_Point * 10);
        if(pips >= InpTP_Pips || curBid <= vSL) trade.PositionClose(_Symbol);
        if(pips >= InpTrailingStart) {
            double newSL = curBid - (InpTrailingStop * _Point * 10);
            if(newSL > vSL) vSL = newSL;
        }
    } else {
        double pips = (openPrice - curAsk) / (_Point * 10);
        if(pips >= InpTP_Pips || curAsk >= vSL) trade.PositionClose(_Symbol);
        if(pips >= InpTrailingStart) {
            double newSL = curAsk + (InpTrailingStop * _Point * 10);
            if(vSL == 0 || newSL < vSL) vSL = newSL;
        }
    }
}

bool PositionSelectByMagic(string sym, long mg) {
    for(int i=PositionsTotal()-1; i>=0; i--) {
        ulong t = PositionGetTicket(i);
        if(PositionSelectByTicket(t) && PositionGetString(POSITION_SYMBOL)==sym && PositionGetInteger(POSITION_MAGIC)==mg) return true;
    }
    return false;
}