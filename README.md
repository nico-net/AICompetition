# AICompetition

This repository contains all the developed source code and the documentation produced for the RF signal classification project. Our implementation focuses on signals operating in the main ISM frequency band (2.40–2.48 GHz), including technologies such as WLAN, Bluetooth, and ZigBee, as well as a non-standard signal based on the SmartBAN specification. The goal of the project is to classify these overlapping signals within the increasingly congested ISM spectrum, with particular attention to future applications in Body Area Networks (BANs).

## HOW TO INSTALL

To access all the materials, follow these steps:

- Copy the repository link: https://github.com/nico-net/AICompetition  
- Open your terminal  
- Run the command:  
  ```bash
  git clone https://github.com/nico-net/AICompetition

## HOW TO USE:

### Folder Structure — `AICompetition`

Inside the folder `AICompetition` in your local environment, you will find the following directories:

---

#### `createDataset`
- Helper functions for signal simulation  
- Signal mixer code used to combine signals within the considered frequency band  
- Interference generator code used to introduce interferences  
- `mainCreatingImages.mlx`: user interface code for dataset creation  
- `creatingTrainingImages.mlx`: detailed script explaining all adopted and developed functionalities  

---

#### `evaluationMetricsSynthetic`
- Semantic segmentation model evaluation code across different SNR levels  
- Use `mainEvaluationMetricsSynthetic.m` to run the evaluation  

---

#### `plutoTxSmartBANAndZigBeeSDR`
- Helper function for ZigBee: generates clean waveform for SDR transmission  
- Helper function for SmartBAN: generates clean waveform for SDR transmission  
- Generator code that uses the helper functions to create and transmit ZigBee or SmartBAN signals via PlutoSDR  
- `mainZigBeeSmartBANTx.mlx`: compact and user-friendly interface script  

---

#### `predictionTime`
- `.mat` files with prediction time values used to compute mean and variance  
- These values are referenced in **Table IV** of the documentation  

---

#### `pruningQuantizationFolder`
- `pruningAndQuantization.m`: end-to-end pruning and quantization pipeline for a ResNet-50 + attention-gated U-Net  
- `projectionFunction.m`: compresses a neural network using neuron-PCA and performs fine-tuning  

---

#### `trainNetworkFolder`
- `trainNetworkDef.m`: source code for training neural networks  
- `trainNetwork.mlx`: compact and user-friendly interface for model training  

---

#### `visualizationFunctionsForSyntheticImages`
- `helperSpecSenseDisplayResults.m`: visualization functions to show predicted and true labels  
- `helperVisualizationPredictedAndTrueLabels.m`: loads samples, segments them with a trained model, and compares true vs. predicted labels  
- `mainVisualizationPredictionsSynthetic.mlx`: user-friendly interface for visualizing predictions  

---

#### `visualizationHelpers`
- `plotOverLayed.m`: overlays a colormapped matrix onto an image  
- `plotResults.m`: visualizes net results by comparing predicted and true labels on an ISM band spectrogram  
- `reAllignLabels.m`: reassigns mask labels to simplify colormapping  
- `rxPluto.m`: performs synchronized IQ acquisition using two ADALM-Pluto SDRs and processes signals for AI-based classification and spectrogram visualization  


## LICENSE:

This project is licensed under the **MIT License**.  
See the [LICENSE](LICENSE) file for more details.
