"""Write small zstd inputs for opt-in Maven/Docker lifecycle validation."""
import csv
from pathlib import Path
import subprocess
import sys

def write(directory, name, header, rows):
    plain = directory / (name + '.plain')
    with plain.open('w', newline='') as f:
        writer = csv.writer(f); writer.writerow(header); writer.writerows(rows)
    subprocess.run(['zstd', '-qf', str(plain), '-o', str(directory / name)], check=True)
    plain.unlink()

if __name__ == '__main__':
    directory = Path(sys.argv[1]); directory.mkdir(parents=True, exist_ok=True)
    write(directory, 'FDVA.csv.zst', ['DATAFLOW','MEASURE','TIME_PERIOD',
        'VALUE_ADDED_SOURCE_AREA','VALUE_ADDED_SOURCE_ACTIVITY','FINAL_DEMAND_AREA',
        'FINAL_DEMAND_ACTIVITY','OBS_VALUE','UNIT_MEASURE','UNIT_MULT','FREQ'], [
        ['FDVA','M',2022,'USA','X','CAN','Y',1.5,'USD',6,'A'],
        ['FDVA','M',2022,'USA','X','CAN','Y','','USD',6,'A'],
        ['FDVA','M',2022,'AGO','X','COD','Y',1,'USD',6,'A'],
        ['FDVA','M',2022,'STP','X','ARE','Y',2,'USD',6,'A']])
