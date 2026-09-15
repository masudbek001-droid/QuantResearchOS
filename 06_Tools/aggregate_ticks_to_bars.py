"""Rebuild Market.db Bars from the append-only tick archive.

Streaming by timeframe keeps memory bounded; existing bars are replaced only
after the new table is complete. Run with MetaTrader closed.
"""
import argparse, os, shutil, sqlite3, tempfile, time

TF = [(1,60),(5,300),(15,900),(30,1800),(60,3600),(240,14400),(1440,86400)]

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--ticks',required=True); ap.add_argument('--market',required=True); ap.add_argument('--backup',required=True); a=ap.parse_args()
    os.makedirs(a.backup,exist_ok=True)
    shutil.copy2(a.market,os.path.join(a.backup,'CBEA_Market.before_tick_aggregation.db'))
    src=sqlite3.connect(a.ticks,uri=False); dst=sqlite3.connect(a.market)
    dst.execute('PRAGMA journal_mode=WAL'); dst.execute('PRAGMA synchronous=NORMAL')
    dst.execute('DROP TABLE IF EXISTS Bars_rebuilt')
    dst.execute('CREATE TABLE Bars_rebuilt AS SELECT * FROM Bars WHERE 0')
    dst.execute('CREATE UNIQUE INDEX uq_bars_rebuilt ON Bars_rebuilt(SymbolID,TimeframeID,OpenTime)')
    # Current Stage 2 scope is XAUUSD (SymbolID=1).  Restricting the scan
    # lets SQLite use idx_tick_btime instead of sorting the whole 40 GB file.
    q="SELECT SymbolID,BrokerTime,Bid,Ask,Last,Volume,Milliseconds FROM Ticks INDEXED BY idx_tick_btime WHERE SymbolID=1 ORDER BY BrokerTime,Milliseconds,TickID"
    states={tf:[None,None,0] for tf,sec in TF}
    def flush(x, tf):
            if x is None: return 0
            sid,t,o,h,l,c,vol,sp=x
            stamp=time.strftime('%Y-%m-%d %H:%M',time.gmtime())
            dst.execute("INSERT OR REPLACE INTO Bars_rebuilt(SymbolID,TimeframeID,OpenTime,Open,High,Low,Close,TickVolume,RealVolume,Spread,Session,Weekday,Month,Quarter,DST,BrokerOffset,DataSourceID,ImportBatchID,ImportedAt) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",(sid,tf,t,o,h,l,c,vol,0,sp,0,0,0,0,0,0,0,0,stamp)); return 1
    for r in src.execute(q):
        sid,bt,bid,ask,last,vol,ms=r; price=last if last and last>0 else bid
        for tf,sec in TF:
            st=states[tf]; key=(sid,(bt//sec)*sec); spread=((ask-bid) if ask and bid else 0.0)
            if st[0] is None or key!=st[0]:
                if st[1] is not None: st[2]+=flush(st[1],tf)
                st[0]=key; st[1]=[sid,key[1],price,price,price,price,int(vol or 0),spread]
            else:
                x=st[1]; x[3]=max(x[3],price); x[4]=min(x[4],price); x[5]=price; x[6]+=int(vol or 0); x[7]=spread
    for tf,st in states.items():
        if st[1] is not None: st[2]+=flush(st[1],tf)
        print(f'PERIOD_{tf}: {st[2]}',flush=True)
    dst.commit()
    dst.execute('DROP TABLE Bars'); dst.execute('ALTER TABLE Bars_rebuilt RENAME TO Bars')
    for sql in ('CREATE INDEX idx_bar_symbol ON Bars(SymbolID)','CREATE INDEX idx_bar_tf ON Bars(TimeframeID)','CREATE INDEX idx_bar_time ON Bars(OpenTime)'):
        dst.execute(sql)
    dst.commit(); src.close(); dst.close(); print('COMPLETE',flush=True)

if __name__=='__main__': main()
