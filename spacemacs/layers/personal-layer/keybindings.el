(spacemacs/declare-prefix "o" "personal-layer")

(when (configuration-layer/package-usedp 'evil-numbers)
  (spacemacs/set-leader-keys
    "o*" 'personal-layer/multiply-at-pt
    "op" 'personal-layer/to-private-event-id
    "oP" 'personal-layer/to-public-event-id
    "ou" 'personal-layer/to-private-user-id
    "oU" 'personal-layer/to-public-user-id))
