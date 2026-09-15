# 05_Training/Datasets

DatasetBuilder CSV exports remain the canonical EA-originated dataset artifacts.

For Stage 8, `06_Tools/train_phase_d_models.py` builds a research-only supervised
training frame directly from integrity-checked `CBEA_Market.db` H1 bars and
writes the materialized feature vectors to `05_Training/FeatureVectors/`.
