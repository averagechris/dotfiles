{lib, ...}: let
  inherit (lib) lists;
  inherit (lib.attrsets) mapAttrsToList removeAttrs;

  isEmpty = lst: builtins.length lst == 0;

  bind_hrm = {
    to,
    mod,
    timeout_ms ? 150,
  }: let
    binding = {
      type = "basic";
      parameters = {
        basic.to_if_alone_timeout_milliseconds = timeout_ms;
        basic.to_if_held_down_threshold_milliseconds = timeout_ms;
      };
      to_if_alone = [{key_code = to;}];
      to_if_held_down = [{key_code = mod;}];
      from = {};
    };
  in [binding];

  bind = {
    to,
    with_mods ? [],
    with_optional_mods ? ["any"],
    mods ? [],
    type ? "basic",
    ...
  } @ kwargs: let
    passed_through = removeAttrs kwargs [
      "to_if_alone"
      "to"
      "with_mods"
      "mods"
      "type"
    ];
    to_if_alone =
      if kwargs ? to_if_alone
      then {
        to_if_alone = [
          {key_code = kwargs.to_if_alone;}
        ];
      }
      else {};
    from_modifiers =
      {}
      // (
        if isEmpty with_mods
        then {}
        else {mandatory = with_mods;}
      )
      // (
        if isEmpty with_optional_mods
        then {}
        else {optional = with_optional_mods;}
      );

    manipulator =
      {
        inherit type;
        from = {
          modifiers = from_modifiers;
        };
        to = [
          {
            key_code = to;
            modifiers = mods;
          }
        ];
      }
      // passed_through
      // to_if_alone;
  in [manipulator];

  bind_set = key: value: {
    with_mods ? [],
    with_optional_mods ? ["any"],
  }: let
    from_modifiers =
      {}
      // (
        if isEmpty with_mods
        then {}
        else {mandatory = with_mods;}
      )
      // (
        if isEmpty with_optional_mods
        then {}
        else {optional = with_optional_mods;}
      );
  in [
    {
      type = "basic";
      from = {
        modifiers = from_modifiers;
      };
      to = [
        {
          set_variable = {
            name = key;
            inherit value;
          };
        }
      ];
    }
  ];

  bind_toggle = name: {
    with_mods ? [],
    with_optional_mods ? ["any"],
  }: let
    from_modifiers =
      {}
      // (
        if isEmpty with_mods
        then {}
        else {mandatory = with_mods;}
      )
      // (
        if isEmpty with_optional_mods
        then {}
        else {optional = with_optional_mods;}
      );
  in [
    {
      type = "basic";
      from = {
        modifiers = from_modifiers;
      };
      to = [
        {
          set_variable = {
            inherit name;
            value = 0;
          };
        }
      ];
      conditions = [
        {
          type = "variable_if";
          inherit name;
          value = 1;
        }
      ];
    }
    {
      type = "basic";
      from = {
        modifiers = from_modifiers;
      };
      to = [
        {
          set_variable = {
            inherit name;
            value = 1;
          };
        }
      ];
      conditions = [
        {
          type = "variable_if";
          inherit name;
          value = 0;
        }
      ];
    }
  ];

  HYPER = [
    "left_shift"
    "left_command"
    "left_control"
    "left_option"
  ];

  bound_when = {
    conditionals,
    describe,
    bindings,
  }: {
    inherit describe;
    manipulators = let
      mapped =
        mapAttrsToList (
          from_key_code: bindingList: let
            mapped =
              map (
                binding: let
                  fromAttrs = {from = binding.from // {key_code = from_key_code;};};
                  conditions =
                    if isEmpty conditionals
                    then {}
                    else {
                      conditions =
                        conditionals
                        ++ (
                          if binding ? "conditions"
                          then binding.conditions
                          else []
                        );
                    };
                in
                  binding
                  // fromAttrs
                  // conditions
              )
              bindingList;
          in
            # builtins.trace "result: ${builtins.toJSON mapped}"
            mapped
        )
        bindings;
    in
      lists.flatten mapped;
  };

  multi_mode = mode_names: bindings:
    bound_when {
      conditionals =
        map (name: {
          type = "variable_if";
          inherit name;
          value = 1;
        })
        mode_names;
      describe = k: "Mode: ${k}";
      inherit bindings;
    };

  mode = name: multi_mode [name];

  layer = name: bindings: let
    l = bound_when {
      conditionals = [
        {
          type = "variable_if";
          name = "active_layer";
          value = name;
        }
      ];
      describe = k: "Layer: ${k}";
      inherit bindings;
    };
    terminate_layer = m: let
      should_terminate = !lib.any (t: (lib.attrByPath ["set_variable" "name"] "" t) == "active_layer") m.to;
    in
      m
      // (
        if should_terminate
        then {
          to =
            m.to
            ++ [
              {
                set_variable = {
                  name = "active_layer";
                  value = 0;
                };
              }
            ];
        }
        else {}
      );
  in
    l // {manipulators = map terminate_layer l.manipulators;};

  globals = bound_when {
    conditionals = [];
    describe = desc: desc;
    bindings = {
      # map caps_lock to hyper
      "caps_lock" = bind {
        to = "left_shift";
        mods = [
          "left_command"
          "left_control"
          "left_option"
        ];
        to_if_alone = "escape";
      };
      "quote" = bind_set "active_layer" "base" {with_mods = HYPER;};
      escape = [
        ((builtins.head (bind_set "active_layer" 0 {}))
          // {
            conditions = [
              {
                name = "active_layer";
                type = "variable_unless";
                value = 0;
              }
            ];
          })
      ];
    };
  };

  modes = {
    home_row_modifiers_colemak = multi_mode ["mode_home_row_modifiers_colemak" "mode_colemak_mod_dh"] {
      a = bind_hrm {
        to = "a";
        mod = "left_option";
      };
      r = bind_hrm {
        to = "r";
        mod = "left_command";
      };
      s = bind_hrm {
        to = "s";
        mod = "left_control";
      };
      t = bind_hrm {
        to = "t";
        mod = "left_shift";
      };
      o = bind_hrm {
        to = "o";
        mod = "right_option";
      };
      i = bind_hrm {
        to = "i";
        mod = "right_command";
      };
      e = bind_hrm {
        to = "e";
        mod = "right_control";
      };
      n = bind_hrm {
        to = "n";
        mod = "right_shift";
      };
    };
    colemak_mod_dh = mode "mode_colemak_mod_dh" {
      e = bind {to = "f";};
      r = bind {to = "p";};
      t = bind {to = "b";};
      y = bind {to = "j";};
      u = bind {to = "l";};
      i = bind {to = "u";};
      o = bind {to = "y";};
      p = bind {to = "semicolon";};
      s = bind {to = "r";};
      d = bind {to = "s";};
      f = bind {to = "t";};
      h = bind {to = "m";};
      j = bind {to = "n";};
      k = bind {to = "e";};
      l = bind {to = "i";};
      "semicolon" = bind {to = "o";};
      z = bind {to = "x";};
      x = bind {to = "c";};
      c = bind {to = "d";};
      b = bind {to = "z";};
      n = bind {to = "k";};
      m = bind {to = "h";};
    };
  };

  layers = {
    base = layer "base" {
      "quote" = bind_toggle "mode_colemak_mod_dh" {};
      "semicolon" = bind_toggle "mode_home_row_modifiers_colemak" {};
      "o" = bind_toggle "mode_home_row_modifiers_colemak" {};
      w = bind_set "active_layer" "window" {};
    };
  };

  modes_to_rules = mds:
    mapAttrsToList (mode_name: bindings: {
      description = bindings.describe mode_name;
      inherit (bindings) manipulators;
    })
    mds;
  # accumulate_manipulators = from: lists.flatten (lists.concatMap (f: mapAttrsToList (k: v: v.manipulators) f) from);
in {
  xdg.configFile."karabiner/assets/complex_modifications/1704067200.json".text = let
    result = builtins.toJSON {
      title = "My karabiner, nix home-manager rules.";
      rules =
        [
          {
            description = globals.describe "Global Keybindings";
            inherit (globals) manipulators;
          }
        ]
        ++ modes_to_rules modes
        ++ modes_to_rules layers;
    };
  in
    # builtins.trace result
    result;
}
