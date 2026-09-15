import argparse, os, shutil, sqlite3, time
TF=((1,60),(5,300),(15,900),(30,1800),(60,3600),(240,14400),(1440,86400))
def main():
 p=argparse.ArgumentParser();p.add_argument('--ticks',required=True);p.add_argument('--market',required=True);p.add_argument('--backup',required=True);p.add_argument('--symbol-id',type=int,default=7);a=p.parse_args()
 os.makedirs(a.backup,exist_ok=True); shutil.copy2(a.market,os.path.join(a.backup,'CBEA_Market.stream.before.db'))
 src=sqlite3.connect(a.ticks,uri=False); dst=sqlite3.connect(a.market,timeout=60); src.execute('PRAGMA mmap_size=1073741824'); src.execute('PRAGMA cache_size=-262144'); dst.execute('PRAGMA journal_mode=WAL'); dst.execute('DELETE FROM Bars WHERE SymbolID=?',(a.symbol_id,)); dst.commit()
 states={tf:None for tf,sec in TF}; made={tf:0 for tf,sec in TF}; seen=0
 cur=src.execute('SELECT SymbolID,BrokerTime,Bid,Ask,Last,Volume,Milliseconds,TickID FROM Ticks INDEXED BY idx_tick_btime WHERE SymbolID=? ORDER BY BrokerTime,Milliseconds,TickID',(a.symbol_id,))
 def emit(tf,x):
  if x is None:return
  sid,t,o,h,l,c,v,sp=x; dst.execute('INSERT OR REPLACE INTO Bars(SymbolID,TimeframeID,OpenTime,Open,High,Low,Close,TickVolume,RealVolume,Spread,Session,Weekday,Month,Quarter,DST,BrokerOffset,DataSourceID,ImportBatchID,ImportedAt) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',(sid,tf,t,o,h,l,c,v,0,sp,0,0,0,0,0,0,0,0,time.strftime('%Y-%m-%d %H:%M'))); made[tf]+=1
 for batch in iter(lambda:cur.fetchmany(50000),[]):
  for sid,bt,bid,ask,last,vol,ms,tid in batch:
   price=last if last and last>0 else bid; seen+=1
   for tf,sec in TF:
    key=(sid,(bt//sec)*sec); x=states[tf]
    if x is None or key!=(x[0],x[1]):
     if x is not None: emit(tf,x[2])
     states[tf]=(sid,key[1],[sid,key[1],price,price,price,price,int(vol or 0),((ask-bid) if ask and bid else 0.0)])
    else:
     z=x[2];z[3]=max(z[3],price);z[4]=min(z[4],price);z[5]=price;z[6]+=int(vol or 0);z[7]=((ask-bid) if ask and bid else 0.0)
  dst.commit()
  if seen%1000000<50000: print('TICKS',seen,'BARS',sum(made.values()),flush=True)
 for tf,x in states.items():
  if x is not None: emit(tf,x[2])
 dst.commit(); print('COUNTS',made,flush=True); src.close();dst.close();print('COMPLETE',flush=True)
if __name__=='__main__':main()
