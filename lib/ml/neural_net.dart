import 'dart:math';

class NeuralNetwork {
  final List<int> layers;
  late List<List<List<double>>> weights;
  late List<List<double>> biases;
  final Random _random = Random();

  NeuralNetwork(this.layers) {
    _initializeWeights();
  }

  void _initializeWeights() {
    weights = [];
    biases = [];
    for (int i = 1; i < layers.length; i++) {
      int prevNodes = layers[i - 1];
      int currentNodes = layers[i];

      List<List<double>> layerWeights = [];
      List<double> layerBiases = [];

      for (int j = 0; j < currentNodes; j++) {
        // Xavier/Glorot initialization for sigmoid
        double limit = sqrt(6.0 / (prevNodes + currentNodes));
        List<double> nodeWeights = [];
        for (int k = 0; k < prevNodes; k++) {
          nodeWeights.add((_random.nextDouble() * 2 - 1) * limit);
        }
        layerWeights.add(nodeWeights);
        layerBiases.add(0.0);
      }
      weights.add(layerWeights);
      biases.add(layerBiases);
    }
  }

  double _sigmoid(double x) {
    return 1.0 / (1.0 + exp(-x));
  }

  double _sigmoidDerivative(double x) {
    return x * (1.0 - x);
  }

  List<double> forward(List<double> inputs) {
    List<double> current = inputs;
    for (int i = 0; i < weights.length; i++) {
      List<double> next = [];
      for (int j = 0; j < weights[i].length; j++) {
        double sum = biases[i][j];
        for (int k = 0; k < weights[i][j].length; k++) {
          sum += current[k] * weights[i][j][k];
        }
        next.add(_sigmoid(sum));
      }
      current = next;
    }
    return current;
  }

  void train(List<List<double>> trainingData, List<List<double>> targets, int epochs, double learningRate) {
    for (int epoch = 0; epoch < epochs; epoch++) {
      for (int i = 0; i < trainingData.length; i++) {
        _backpropagate(trainingData[i], targets[i], learningRate);
      }
    }
  }

  void _backpropagate(List<double> input, List<double> target, double learningRate) {
    // 1. Forward Pass with layer cache
    List<List<double>> activations = [input];
    List<double> current = input;

    for (int i = 0; i < weights.length; i++) {
      List<double> next = [];
      for (int j = 0; j < weights[i].length; j++) {
        double sum = biases[i][j];
        for (int k = 0; k < weights[i][j].length; k++) {
          sum += current[k] * weights[i][j][k];
        }
        next.add(_sigmoid(sum));
      }
      current = next;
      activations.add(current);
    }

    // 2. Backward Pass
    List<double> expected = target;
    List<List<double>> deltas = List.filled(weights.length, []);

    for (int i = weights.length - 1; i >= 0; i--) {
      List<double> layerDeltas = [];
      List<double> layerActivations = activations[i + 1];

      if (i == weights.length - 1) {
        // Output layer error
        for (int j = 0; j < layerActivations.length; j++) {
          double error = expected[j] - layerActivations[j];
          layerDeltas.add(error * _sigmoidDerivative(layerActivations[j]));
        }
      } else {
        // Hidden layer error
        List<List<double>> nextWeights = weights[i + 1];
        List<double> nextDeltas = deltas[i + 1];

        for (int j = 0; j < layerActivations.length; j++) {
          double error = 0.0;
          for (int k = 0; k < nextDeltas.length; k++) {
            error += nextDeltas[k] * nextWeights[k][j];
          }
          layerDeltas.add(error * _sigmoidDerivative(layerActivations[j]));
        }
      }
      deltas[i] = layerDeltas;
    }

    // 3. Update Weights and Biases
    for (int i = 0; i < weights.length; i++) {
      List<double> layerInput = activations[i];
      for (int j = 0; j < weights[i].length; j++) {
        for (int k = 0; k < weights[i][j].length; k++) {
          weights[i][j][k] += learningRate * deltas[i][j] * layerInput[k];
        }
        biases[i][j] += learningRate * deltas[i][j];
      }
    }
  }
}
