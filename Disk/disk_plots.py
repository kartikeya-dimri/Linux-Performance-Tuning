import os
import pandas as pd
import matplotlib.pyplot as plt

before_dir = input("Enter BEFORE directory path: ").strip()
after_dir = input("Enter AFTER directory path: ").strip()

def load_features(path):
    return pd.read_json(os.path.join(path, "disk_features_full.json"), typ="series")

before = load_features(before_dir)
after = load_features(after_dir)

metrics = ["avg_await", "avg_queue", "avg_util", "avg_iops", "avg_iowait"]

os.makedirs("comparison_plots", exist_ok=True)

for m in metrics:
    plt.figure()
    plt.bar(["Before", "After"], [before[m], after[m]])
    plt.title(m)
    plt.savefig(f"comparison_plots/{m}.png")
    plt.close()

print("[+] Plots saved in comparison_plots/")