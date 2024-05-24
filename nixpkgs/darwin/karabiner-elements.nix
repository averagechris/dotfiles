{
  config,
  lib,
  ...
}: let
  inherit (lib) attrByPath foldl' lists mapAttrs mkEnableOption mkOption recursiveUpdate;
  inherit (lib.attrsets) filterAttrs mapAttrsToList;

  cfg = config.programs.karabiner-elements;

  isEmpty = lst: builtins.length lst == 0;
  rmNulls = filterAttrs (k: v: v != null);
  types =
    lib.types
    // {
      conditions = types.listOf (types.submodule {
        options = {
          type = mkOption {
            type = types.enum ["variable_if" "variable_unless"];
            default = types.unspecified;
          };
          name = mkOption {
            type = types.str;
            default = types.unspecified;
          };
          value = mkOption {
            type = types.either types.str types.int;
            default = types.unspecified;
          };
        };
      });
      kb_modifiers = types.enum [
        "left_option"
        "left_command"
        "left_control"
        "left_shift"
        "right_option"
        "right_command"
        "right_control"
        "right_shift"
        "option"
        "command"
        "control"
        "shift"
        "any"
      ];
      # Meant to represent a simple mapping or a list of "to events", see the karabiner docs
      to_keys = types.either types.str (types.listOf types.attrs); # TODO should types.str be an enum?=
      manipulator_type = types.enum ["basic" "mouse_motion_to_scroll"];
    };

  bind.options = {
    description = {
      type = types.str;
      description = "The string used to describe a specific binding (manipulator) of a rule within the karabiner-elements gui.";
      default = "";
      example = null;
    };
    mandatory_modifiers = {
      type = types.listOf types.kb_modifiers;
      description =
        ''Any modifiers that are required for this binding to match.\n''
        + ''For example: if mapping left_command + e => escape, set `mandatory_modifiers = ["left_command"]`.'';
      default = [];
      example = ["left_command"];
    };

    optional_modifiers = {
      type = types.listOf types.kb_modifiers;
      description =
        ''Any modifiers that are allowed, but not required for this binding to match.\n''
        + ''For example: if mapping e => escape, or E => escape, set `optional_modifiers = ["left_shift" "right_shift"]`.'';
      default = [];
      example = ["right_shift" "left_shift"];
    };
    to = {
      type = types.to_keys;
      description =
        ''The key that this binding results in.\n''
        + ''For example: if binding a => b, set `to = "b"`.\n''
        + "Leave this null to make it so a binding that only produces side effects "
        + "without mapping it to another key.\n"
        + ''This can also be a list of "to event" attrs for more complex mappings.\n''
        + "See: https://karabiner-elements.pqrs.org/docs/json/complex-modifications-manipulator-definition/to/";
      default = [];
      example = "b";
    };
    if_held = {
      type = types.to_keys;
      description =
        ''The key that this binding results in only if the bound key(s) are held down.\n''
        + ''For example: if binding a => left_alt, when a is held down, set `if_held = "left_alt"`.'';
      default = [];
      example = "left_alt";
    };
    if_alone = {
      type = types.to_keys;
      description =
        ''The key that this binding results in only if the bound key is unmodified.\n''
        + ''For example: if binding a => left_alt, when a is held down, but leavining\n''
        + ''it as a otherwise, set `{if_alone = "a"; if_held = "left_alt"; ...}`'';
      default = [];
      example = "a";
    };
    after_key_up = {
      type = types.to_keys;
      description =
        "Useful for producing side effects that run after key up like reseting modes or layers.\n"
        + "See: https://karabiner-elements.pqrs.org/docs/json/complex-modifications-manipulator-definition/to-after-key-up/";
      default = [];
      example = [
        {
          set_variable = {
            name = "active_layer";
            value = 0;
          };
        }
      ];
    };
    delayed_action = {
      type = types.nullOr (types.submodule {
        options = {
          if_invoked = mkOption {
            type = types.to_keys;
            default = [];
          };
          if_canceled = mkOption {
            type = types.to_keys;
            default = [];
          };
        };
      });
      description =
        ''Send some "to" events after a timeout. Among other things, this is useful for clearing mode and layer variables.\n''
        + "https://karabiner-elements.pqrs.org/docs/json/complex-modifications-manipulator-definition/to-delayed-action/";
      default = null;
      example = {
        if_invoked = [
          {
            set_variable = {
              name = "mode__my_transient_mode";
              value = 0;
            };
          }
        ];
        if_canceled = [];
      };
    };
    set_variables = {
      type = types.listOf (types.submodule {
        options = {
          name = mkOption {
            type = types.str;
          };
          value = mkOption {
            type = types.nullOr (types.either types.str types.int);
          };
          key_up_value = mkOption {
            type = types.nullOr (types.either types.str types.int);
          };
        };
      });
      description = "Use this to introduce optional side effects of this binding by setting variables.";
      default = [];
      example = [
        {
          name = "mode__colemak_mod_dh";
          value = 1;
          key_up_value = 0;
        }
      ];
    };
    conditions = {
      type = types.conditions;
      description = ''Used to make a binding only apply in some situations, like if a mode is active.'';
      example = [
        {
          type = "variable_if";
          name = "mode_active__colemak_mod_dh";
          value = 1;
        }
      ];
      default = [];
    };
    type = {
      type = types.manipulator_type;
      description =
        "See karabiner-elements docs. This should almost always be basic which is the default.\n"
        + "https://karabiner-elements.pqrs.org/docs/json/complex-modifications-manipulator-definition/other-types/";
      example = "basic";
      default = "basic";
    };
    open = {
      type = types.nullOr types.str;
      description = "Makes a side effect to open an app bundle via shell command `open -a`.";
      default = null;
      example = "Finder.app";
    };
    raycast = {
      type = types.nullOr types.str;
      description = "Makes a side effect to open an action in raycast via deeplinks.";
      default = null;
      example = "extensions/raycast/raycast-ai/ai-chat";
    };
    toggle_modes = {
      type = types.listOf types.str;
      description = "Makes a side effect that toggles on or off a list modes by setting each mode's variable to 1 or 0.";
      default = [];
      example = ["my_mode"];
    };
    shell_command = {
      type = types.nullOr types.str;
      description =
        "Makes a side effect that runs a shell command.\n"
        + "see https://karabiner-elements.pqrs.org/docs/json/complex-modifications-manipulator-definition/to/shell-command/";
      default = null;
      example = "export LC_ALL=en_US.UTF-8; pbpaste | tr '[:upper:]' '[:lower:]' | pbcopy";
    };
    parameters = {
      type = types.nullOr types.attrs;
      description = "";
      default = null;
      example = {
        basic.to_if_alone_timeout_milliseconds = 150;
        basic.to_if_held_down_threshold_milliseconds = 150;
      };
    };
  };

  # str -> {from_key_code: bind.options} -> {title = str, manipulators = [...];}
  into_rule = description: bindings: let
    to_events_from = binding: let
      # NOTE in this to_events_from function, access attributes of `binding` carefully cause it's reused
      # for `to` `to_if_alone` and all of the other variants that can produce side effects
      to_is_str = lib.isString binding.to;
      complex_to =
        if (!to_is_str)
        then binding.to
        else [];
      simple_to = let
        key_code =
          if to_is_str
          then lib.toLower binding.to
          else "";
      in
        if to_is_str
        then [
          ({inherit key_code;}
            // (
              # add shift if this is an uppercase letter
              if key_code != binding.to
              then {modifiers = ["left_shift"];}
              else {}
            ))
        ]
        else [];
      side_effects =
        lists.flatten [
          (
            lib.optional ((attrByPath ["open"] null binding) != null) {
              shell_command = "open -a ${binding.open}";
            }
          )
          (
            lib.optional ((attrByPath ["raycast"] null binding) != null) {
              shell_command = "open raycast://${binding.raycast}";
            }
          )
          (
            lib.optional ((attrByPath ["shell_command"] null binding) != null) {
              shell_command = "${binding.shell_command}";
            }
          )
        ]
        ++ (map (v: {set_variable = rmNulls v;}) (
          if (binding ? "set_variables")
          then binding.set_variables
          else []
        ));
    in
      simple_to ++ complex_to ++ side_effects;
  in {
    inherit description;
    # TODO toggle_modes requires 2 copies of the manipulator. 1 with the set var 1 to event appended + condition 0
    # and one with the opposite
    manipulators = mapAttrsToList (key_code: binding: (foldl' recursiveUpdate {
        inherit (binding) type;
        from.key_code = lib.toLower key_code;
      } [
        (
          if builtins.stringLength binding.description == 0
          then {}
          else {inherit (binding) description;}
        )
        # implicitly add left shift if an uppercase letter was used to express this binding e.g. "F".to = "...";
        (
          if ((lib.toLower key_code) != key_code)
          then {from.modifiers.mandatory = ["shift"];}
          else {}
        )
        # # add passed in from modifiers if any, overriding the implicit modifier above
        (
          if (!isEmpty binding.mandatory_modifiers)
          then {from.modifiers.mandatory = binding.mandatory_modifiers;}
          else {}
        )
        (
          if (!isEmpty binding.optional_modifiers)
          then {from.modifiers.optional = binding.optional_modifiers;}
          else {}
        )
        # # include collected to events constructed from simple mappings and side effects
        (
          let
            to = to_events_from binding;
          in
            if (!(isEmpty to))
            then {inherit to;}
            else {}
        )
        (
          let
            to_if_alone = to_events_from {to = binding.if_alone;};
          in
            if (!isEmpty to_if_alone)
            then {inherit to_if_alone;}
            else {}
        )
        (
          let
            to_if_held_down = to_events_from {to = binding.if_held;};
          in
            if (!isEmpty to_if_held_down)
            then {inherit to_if_held_down;}
            else {}
        )
        (
          let
            to_after_key_up = to_events_from {to = binding.after_key_up;};
          in
            if (!isEmpty to_after_key_up)
            then {inherit to_after_key_up;}
            else {}
        )
        (
          let
            to_if_invoked = to_events_from {to = attrByPath ["delayed_action" "if_invoked"] [] binding;};
          in
            if (!isEmpty to_if_invoked)
            then {to_delayed_action.to_if_invoked = to_if_invoked;}
            else {}
        )
        (
          let
            to_if_cancelled = to_events_from {to = attrByPath ["delayed_action" "if_cancelled"] [] binding;};
          in
            if (!isEmpty to_if_cancelled)
            then {to_delayed_action.to_if_cancelled = to_if_cancelled;}
            else {}
        )
        (
          if isEmpty binding.conditions
          then {}
          else {inherit (binding) conditions;}
        )
        (
          if (attrByPath ["parameters"] null binding != null)
          then {inherit (binding) parameters;}
          else {}
        )
      ]))
    bindings;
  };

  mode_into_rule = name: mode: let
    bindings = mapAttrs (k: v:
      v
      // {
        conditions =
          v.conditions
          ++ [
            {
              type = "variable_if";
              name = "mode__${name}";
              value = 1;
            }
          ];
      })
    mode.bind;
  in
    into_rule "Mode ${name}" bindings;

  layer_into_rule = from_key: layer: parent: let
    # TODO FIXME with nested layers we can get a straggling manipulator with no `to` events
    bindings =
      if layer.layer == null
      then layer
      else layer.layer;
    when_layer_active = mapAttrs (k: v:
      v
      // {
        conditions =
          v.conditions
          ++ [
            {
              type = "variable_if";
              name = "active_layer";
              value = layer.unique_name;
            }
          ];
      })
    bindings;

    with_set_active =
      when_layer_active
      // {
        # add a binding, but fill in all the defaults from bind.options
        # to keep things compatible
        "${from_key}" =
          (mapAttrs (k: v: v.default) bind.options)
          // {
            # also fill in layer_submodule defaults for compatability
            layer = null;
            unique_name = null;
            inherit (layer) mandatory_modifiers optional_modifiers;
            set_variables = [
              {
                name = "active_layer";
                value = layer.unique_name;
              }
            ];
            conditions =
              if parent == null
              then []
              else [
                {
                  type = "variable_if";
                  name = "active_layer";
                  value = parent.unique_name;
                }
              ];
          };
      };
    rule = into_rule "Layer ${layer.unique_name}" with_set_active;
    nested_layers = filterAttrs (k: v: let
      l = attrByPath ["layer"] null v;
      n = attrByPath ["unique_name"] null v;
    in
      if (n == null && l != null)
      then builtins.throw ''A layer must define a unique_name. e.g. `layers.a = {unique_name = "MISSING"; layer = {...}}`''
      else l != null)
    layer.layer;
    nested_layer_rules = mapAttrsToList (k: l: layer_into_rule k l layer) nested_layers;
  in
    # builtins.trace bindings
    [rule] ++ nested_layer_rules;

  optionize = opts: {
    options = mapAttrs (k: v: (
      if (attrByPath ["_type"] null v) == "option"
      then v
      else mkOption v
    )) (foldl' recursiveUpdate {} opts);
  };

  layer_submodule = optionize [
    bind.options
    {
      unique_name = {
        type = types.nullOr types.str;
        description = "The name of this layer. It's unique name is used to determine if this layer is active or not.";
        default = null;
        example = "application_launching";
      };
      layer = {
        type = types.nullOr (types.attrsOf (types.submodule layer_submodule));
        description =
          "Any bindings that you want to apply when this layer is the `active_layer`."
          + " There is only one active layer at a time.";
        default = null;
        # example = {};
      };
    }
  ];

  hyper_option = mkOption {
    description = "Configures a hyper rule that creates a binding of caps_lock to hyper by default.";
    type = types.submodule (optionize [
      bind.options
      {
        enable = mkEnableOption "Enable the hyper rule.";
        description = {
          type = types.str;
          description = "The hyper rule describtion in the karabiner-elements ui and config file.";
          default = "Enable caps_lock to behave as a hyper key modifier, or escape if pressed alone.";
        };
        from = {
          type = types.str;
          description = "The key to bind to hyper.";
          default = "caps_lock";
          example = "caps_lock";
        };
        # optional_modifiers.default = ["any"];
        to.default = [
          {
            set_variable = {
              name = "hyper";
              value = 1;
              key_up_value = 0;
            };
          }
          {
            key_code = "left_shift";
            modifiers = [
              "left_command"
              "left_control"
              "left_option"
            ];
          }
        ];
        if_alone.default = "escape";
      }
    ]);
  };
in {
  options = {
    programs.karabiner-elements = {
      enable = mkEnableOption "enables karabiner-elements with custom config.";
      hyper = hyper_option;
      modes = mkOption {
        type = types.attrsOf (types.submodule {
          options = {
            bind = mkOption {
              type = types.attrsOf (types.submodule (optionize [bind.options]));
              description = "Any bindings that you want to apply when this mode is active.";
              default = {};
              example = {
                e.to = "f";
                a.if_held = "left_option";
                t.open = "Terminal.app";
                T.open = "TextEdit.app";
                escape.toggle_modes = ["mode_name"];
              };
            };
          };
        });
        description = "Modes are related sets of bindings that can be enabled or disabled together.";
        default = {};
        example = {
          colemak_mod_dh.bind = {
            e.to = "f";
            r.to = "p";
            t.to = "b";
          };
        };
      };
      layers = mkOption {
        type = types.attrsOf (types.submodule layer_submodule);
        description = "";
        default = {};
        example = {};
      };
    };
  };

  config = lib.mkIf cfg.enable {
    services.karabiner-elements.enable = lib.mkDefault true;
    environment.etc."karabiner/assets/complex_modifications/1704067200.json".text = let
      result = builtins.toJSON {
        title = "nix-darwin configured rules.";
        rules =
          [
            (into_rule cfg.hyper.description {"${cfg.hyper.from}" = cfg.hyper;})
          ]
          ++ mapAttrsToList mode_into_rule cfg.modes
          ++ mapAttrsToList (k: v: layer_into_rule k v null) cfg.layers;
      };
    in
      builtins.trace result
      result;
  };
}
