(when (configuration-layer/package-usedp 'evil-numbers)
  (spacemacs/set-leader-keys
    "op" 'personal-layer/to-private-event-id
    "oP" 'personal-layer/to-public-event-id
    "ou" 'personal-layer/to-private-user-id
    "oU" 'personal-layer/to-public-user-id))
