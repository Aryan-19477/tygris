import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
import train_embedding as te

te.EPOCHS = 1
te.STEPS_PER_EPOCH = 5
te.main()
