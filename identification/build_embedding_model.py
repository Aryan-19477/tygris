"""Convert the closed-set Tiger_Trace ResNet50 classifier into an open-set
embedding model: keep the tiger-adapted backbone + 512-d dense layer,
drop the 107-way softmax head, add L2 normalization for cosine similarity.
"""
from pathlib import Path

import tensorflow as tf
from tensorflow.keras import layers, Model

SOURCE_WEIGHTS = Path(__file__).parent.parent / "resnet50_model_weights.weights.h5"
FINETUNED_WEIGHTS = Path(__file__).parent / "models" / "tiger_embedding_finetuned.weights.h5"
EMBED_DIM = 512
INPUT_SHAPE = (200, 250, 3)
NUM_SOURCE_CLASSES = 107


def _build_source_architecture(input_shape=INPUT_SHAPE, num_classes=NUM_SOURCE_CLASSES):
    """Rebuild the exact Tiger_Trace architecture from scratch (ResNet50 ->
    GAP -> Dense(512, relu) -> Dense(107, softmax)) so weights can be loaded
    by name, sidestepping Keras's fragile from_config reconstruction of the
    original nested-Sequential save (which errors on newer Keras versions)."""
    resnet = tf.keras.applications.ResNet50(
        weights=None, include_top=False, input_shape=input_shape)
    resnet._name = "resnet50"

    model = tf.keras.Sequential([
        tf.keras.Input(shape=input_shape),
        resnet,
        layers.GlobalAveragePooling2D(name="global_average_pooling2d_1"),
        layers.Dense(512, activation="relu", name="dense_2"),
        layers.Dense(num_classes, activation="softmax", name="dense_3"),
    ])
    return model


def build_embedding_model(weights_path=SOURCE_WEIGHTS, embed_dim=EMBED_DIM,
                           finetuned_weights_path=None, augment=True, dropout_rate=0.4):
    """`augment`/`dropout_rate` exist to fight overfitting on the ~1,900-image
    / 107-identity fine-tuning set (see train_embedding.py's module
    docstring): both the augmentation layers and Dropout are Keras layers
    that automatically no-op when the model is called with training=False
    (as evaluate_embeddings.py's model.predict() does), so eval/inference is
    unaffected — they only perturb/drop during the training-loop's explicit
    `model(images, training=True)` calls."""
    source = _build_source_architecture()
    source.load_weights(str(weights_path))

    # cut the graph right after dense_2 (512-d), before the 107-way softmax head.
    input_shape = source.input_shape[1:]
    inputs = layers.Input(shape=input_shape)
    x = inputs

    if augment:
        # Train-time-only perturbations, since this dataset has too few
        # images per identity for the model to see meaningful variation
        # otherwise. Values are mild — tiger stripe patterns are the
        # discriminative signal, so avoid aggressive crops/rotations that
        # would erase the flank markings themselves.
        x = layers.RandomFlip("horizontal", name="aug_flip")(x)
        x = layers.RandomRotation(0.04, name="aug_rotate")(x)
        x = layers.RandomZoom(0.08, name="aug_zoom")(x)
        x = layers.RandomContrast(0.15, name="aug_contrast")(x)
        x = layers.RandomBrightness(0.15, value_range=(0, 255), name="aug_brightness")(x)

    for layer in source.layers:
        x = layer(x)
        if layer.name == "dense_2":
            break

    if dropout_rate > 0:
        x = layers.Dropout(dropout_rate, name="embedding_dropout")(x)

    x = layers.Lambda(lambda t: tf.math.l2_normalize(t, axis=1), name="l2_normalize")(x)
    embed_model = Model(inputs=inputs, outputs=x, name="tiger_embedding_model")

    if finetuned_weights_path is not None:
        embed_model.load_weights(str(finetuned_weights_path))

    return embed_model


if __name__ == "__main__":
    model = build_embedding_model()
    model.summary()
    print("input shape:", model.input_shape)
    print("output shape (embedding dim):", model.output_shape)
