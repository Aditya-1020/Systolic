import torch
import torch.nn as nn
import torch.optim as optim
import torchvision
import torchvision.transforms as transforms
import numpy as np
import os

BATCH_SIZE = 128
EPOCH = 5
LR = 1e-3
DEVICE = torch.device("cpu")
SAVE_DIR = "weights"
DATA_DIR = 