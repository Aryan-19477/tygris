"""Batch-hard triplet loss for metric learning.

For each anchor in a batch, mines the hardest positive (same identity,
furthest away) and hardest negative (different identity, closest) and
pushes the model to satisfy: d(anchor, hardest_positive) + margin <
d(anchor, hardest_negative). This is the standard "batch hard" strategy
from In Defense of the Triplet Loss (Hermans et al. 2017) and is what
makes different-identity embeddings actually separate, unlike a plain
softmax-derived feature space.
"""
import tensorflow as tf


def pairwise_distances(embeddings):
    # embeddings are L2-normalized, so squared euclidean distance
    # relates directly to cosine similarity: ||a-b||^2 = 2 - 2*cos_sim
    dot = tf.matmul(embeddings, embeddings, transpose_b=True)
    sq_norm = tf.linalg.diag_part(dot)
    dist = tf.expand_dims(sq_norm, 0) - 2.0 * dot + tf.expand_dims(sq_norm, 1)
    dist = tf.maximum(dist, 0.0)
    return dist


def batch_hard_triplet_loss(labels, embeddings, margin=0.3):
    labels = tf.reshape(labels, [-1])
    pairwise_dist = pairwise_distances(embeddings)

    labels_equal = tf.equal(tf.expand_dims(labels, 0), tf.expand_dims(labels, 1))
    n = tf.shape(labels)[0]
    identity_mask = tf.eye(n, dtype=tf.bool)

    positive_mask = tf.logical_and(labels_equal, tf.logical_not(identity_mask))
    negative_mask = tf.logical_not(labels_equal)

    # hardest positive: max distance among same-identity pairs
    positive_dist = tf.where(positive_mask, pairwise_dist, tf.zeros_like(pairwise_dist))
    hardest_positive = tf.reduce_max(positive_dist, axis=1)

    # hardest negative: min distance among different-identity pairs
    max_dist = tf.reduce_max(pairwise_dist)
    negative_dist = tf.where(negative_mask, pairwise_dist, max_dist * tf.ones_like(pairwise_dist))
    hardest_negative = tf.reduce_min(negative_dist, axis=1)

    triplet_loss = tf.maximum(hardest_positive - hardest_negative + margin, 0.0)
    return tf.reduce_mean(triplet_loss)
