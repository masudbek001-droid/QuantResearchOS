import argparse, os, shutil, sqlite3, time
TF=((1,60),(5,300),(15,900),(30,1800),(60,3600),(240,14400),(1440,86400))
def main():
 p=argparse.ArgumentParser();p.add_argument('--ticks',required=True);p.add_argument('--market',required=True);p.add_argument('--backup',required=True);p.add_argument('--symbol-id',type=int,default=7);a=p.parse_args()
 os.makedirs(a.backup,exist_ok=True); shutil.copy2(a.market,os.path.join(a.backup,'CBEA_Market.sql.before.db'))
 d=sqlite3.connect(a.market,timeout=60); d.execute('PRAGMA journal_mode=WAL');d.execute('PRAGMA synchronous=NORMAL'); d.execute('ATTACH DATABASE ? AS src',(a.ticks,))
 d.execute('DROP INDEX IF EXISTS uq_rebuilt');d.execute('DROP TABLE IF EXISTS Bars_rebuilt');d.execute('CREATE TABLE Bars_rebuilt AS SELECT * FROM Bars WHERE 0');d.execute('CREATE UNIQUE INDEX uq_rebuilt ON Bars_rebuilt(SymbolID,TimeframeID,OpenTime)')
 for tf,sec in TF:
  sql=f'''WITH p AS (SELECT SymbolID,BrokerTime,Milliseconds,TickID,COALESCE(NULLIF(Last,0),Bid) price,COALESCE(Volume,0) vol,COALESCE(Ask-Bid,0) spr,(BrokerTime/{sec})*{sec} bt FROM main.Ticks WHERE SymbolID={a.symbol_id}), a AS (SELECT SymbolID,bt,MIN(TickID) first_id,MAX(TickID) last_id,MAX(price) hi,MIN(price) lo,SUM(vol) vol,AVG(spr) spr FROM p GROUP BY SymbolID,bt) INSERT INTO Bars_rebuilt(SymbolID,TimeframeID,OpenTime,Open,High,Low,Close,TickVolume,RealVolume,Spread,Session,Weekday,Month,Quarter,DST,BrokerOffset,DataSourceID,ImportBatchID,ImportedAt) SELECT a.SymbolID,{tf},a.bt,p1.price,a.hi,a.lo,p2.price,a.vol,0,a.spr,0,0,0,0,0,0,0,0,datetime('now') FROM a JOIN p p1 ON p1.TickID=a.first_id JOIN p p2 ON p2.TickID=a.last_id'''
  d.execute(sql.replace('main.Ticks','src.Ticks'));d.commit();print('PERIOD_'+str(tf),flush=True)
 d.execute('DROP TABLE Bars');d.execute('ALTER TABLE Bars_rebuilt RENAME TO Bars')
 for x in ('CREATE INDEX idx_bar_symbol ON Bars(SymbolID)','CREATE INDEX idx_bar_tf ON Bars(TimeframeID)','CREATE INDEX idx_bar_time ON Bars(OpenTime)'):d.execute(x)
 d.commit();d.close();print('COMPLETE',flush=True)
if __name__=='__main__':main()
