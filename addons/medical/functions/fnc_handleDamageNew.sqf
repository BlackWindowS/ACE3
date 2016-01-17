/*
 * Author: KoffeinFlummi, Glowbal, commy2
 * Main HandleDamage EH function.
 *
 * Arguments:
 * 0: Unit That Was Hit <OBJECT>
 * 1: Name Of Hit Selection <STRING>
 * 2: Amount Of Damage <NUMBER>
 * 3: Shooter <OBJECT>
 * 4: Projectile <OBJECT/STRING>
 * 5: HitPointIndex (-1 for structural) <NUMBER>
 *
 * Return Value:
 * Damage To Be Inflicted <NUMBER>
 *
 * Public: No
 */
#include "script_component.hpp"

params ["_unit", "_selection", "_damage", "_shooter", "_projectile", "_hitPointIndex"];
TRACE_6("ACE_DEBUG: HandleDamage Called",_unit, _selection, _damage, _shooter, _projectile,_hitPointIndex);

// bug, apparently can fire for remote units in special cases
if !(local _unit) exitWith {
    TRACE_2("ACE_DEBUG: HandleDamage on remote unit!",_unit,isServer);
    nil
};

// bug, assumed fixed, @todo excessive testing, if nothing happens remove
if (typeName _projectile == "OBJECT") then {
    TRACE_3("ACE_DEBUG: HandleDamage found projectile instead of classname of ammo!",_unit,_projectile,typeOf _projectile);
    _projectile = typeOf _projectile;
};

// Exit now we disable damage, replaces "allowDamage false"
if !(_unit getVariable [QGVAR(allowDamage), true]) exitWith {
    TRACE_2("ACE_DEBUG: HandleDamage damage disabled.",_selection,_unit);
    if (_selection == "") then {
        damage _unit
    } else {
        _unit getHit _selection
    };
};

// If damage is in dummy hitpoints, "hands" and "legs", don't change anything
if (_selection == "hands") exitWith {_unit getHit "hands"};
if (_selection == "legs") exitWith {_unit getHit "legs"};
if (_selection == "arms") exitWith {_unit getHit "arms"};

// Deal with the new hitpoint and selection names introduced with Arma v1.50 and later.
// This will convert new selection names into selection names that the medical system understands
// TODO This should be cleaned up when we revisit the medical system at a later stage
// and instead we should deal with the new hitpoints directly
_selection = [_unit, _selection, _hitPointIndex] call FUNC(translateSelections);

// diag_log text format ["HD: Sel[%1] Dam[%2]", _selection, _damage];

// systemChat format["_selection %1 _damage %2", _selection, _damage];

private ["_damageReturn", "_newDamage", "_index"];

// apply damage scripted
if (_selection == "") then {
    _damageReturn = _damage;
    _newDamage = _damage - damage _unit;

    _index = -1;

    private _cachedStructuralDamage = _unit getVariable [QGVAR(cachedStructuralDamageNew), 0];

    // handle damage always tries to start and end with the same structural damage call. Use that to find and set the final damage. discard everything the game discards too.
    // this correctly handles: bullets, explosions, fire
    if (_damage == _cachedStructuralDamage) then {
        private _cachedNewHitpointDamages = _unit getVariable [QGVAR(cachedNewHitpointDamages), [0,0,0,0,0,0]];
        private _cachedNewHitpointProjectiles = _unit getVariable [QGVAR(cachedNewHitpointProjectiles), ["", "", "", "", "", ""]];

        // this is the only point damage actually counts. all additional vitality functions should use these values.
        {
            if (_x > 0) then {
                diag_log text format ["Sel Dam Event %1", [_unit, GVAR(Selections) select _forEachIndex, _x, _cachedNewHitpointProjectiles select _forEachIndex]];
                ["medical_selectionDamage", [_unit, GVAR(Selections) select _forEachIndex, _x, _cachedNewHitpointProjectiles select _forEachIndex]] call EFUNC(common,localEvent);
            };
        } forEach _cachedNewHitpointDamages;
    } else {
        scopeName "findDamageSource";

        // check for fall damage. this triggers twice, but seems to happen on the same frame. shouldn't fall twice in a few frames anyway. tested at 7FPS on local host MP
        if (animationState _unit select [0,4] == "afal") then {
            private "_cachedLastFallDamageFrame";
            _cachedLastFallDamageFrame = _unit getVariable [QGVAR(cachedLastFallDamageFrame), -1];

            if (diag_frameno != _cachedLastFallDamageFrame) then {
                ["medical_fallDamage", [_unit, _newDamage]] call EFUNC(common,localEvent);
                _unit setVariable [QGVAR(cachedLastFallDamageFrame), diag_frameno];
            };

            _damageReturn = damage _unit;
            breakOut "findDamageSource";
        };

        // check for drowning damage. Pretty relyable damage output. triggers only once.
        if (getOxygenRemaining _unit < 0.5) then {
            // typical drowning damage
            if (_newDamage == 0.005) then {
                ["medical_drowningDamage", [_unit, _newDamage]] call EFUNC(common,localEvent);
                _damageReturn = damage _unit - 0.005; // engine applies damage before hd call. subtract again here.
                breakOut "findDamageSource";
            };

            // suffocated under water might use atypical new damage (mostly 1.005)
            if (getOxygenRemaining _unit == 0) then {
                ["medical_drowningDamage", [_unit, _newDamage min 1]] call EFUNC(common,localEvent);
                _damageReturn = damage _unit; // you will die regardless of hd return value
                breakOut "findDamageSource";
            };
        };

        // check for misc. damage. Probably collision.
        if (_projectile == "" && _newDamage > 0) then {
            private "_cachedLastCollisionDamageFrame";
            _cachedLastCollisionDamageFrame = _unit getVariable [QGVAR(cachedLastFallDamageFrame), -1];

            // collision only happens once. engine ignores all further calls on that frame as well
            if (_cachedLastCollisionDamageFrame != diag_frameno) then {
                _unit setVariable [QGVAR(cachedLastFallDamageFrame), diag_frameno];
                _unit setVariable [QGVAR(cachedLastCollisionDamage), 0];

                ["medical_collisionDamage", [_unit, _newDamage max (_unit getVariable [QGVAR(cachedLastCollisionDamage), 0])]] call EFUNC(common,localEvent);

                _damageReturn = damage _unit - _newDamage;
                breakOut "findDamageSource";
            };
            _damageReturn = damage _unit;
        };
    };

    // reset everything, get ready for the next bullet
    _unit setVariable [QGVAR(cachedNewHitpointDamages), [0,0,0,0,0,0]];
    _unit setVariable [QGVAR(cachedNewHitpointProjectiles), ["", "", "", "", "", ""]];
    _unit setVariable [QGVAR(cachedStructuralDamageNew), _damage];

} else {
    // selections are done scripted. return same value to change nothing.
    _damageReturn = _unit getHitIndex _hitPointIndex;
    _newDamage = _damage - _damageReturn; // _damageReturn because it saves one getHit call

    if (_newDamage <= 0) exitWith {
        if (_newDamage < 0) then {
            diag_log text format ["Negative Damage - %1", _newDamage];
        };
    };

    _index = GVAR(SELECTIONS) find _selection;

    // a selection we care for was hit. now save the new damage to apply it by a later structural damage call
    if (_index != -1) then {
        private _cachedNewHitpointDamages = _unit getVariable [QGVAR(cachedNewHitpointDamages), [0,0,0,0,0,0]];
        private _cachedNewHitpointProjectiles = _unit getVariable [QGVAR(cachedNewHitpointProjectiles), ["", "", "", "", "", ""]];

        // prevents multiple selections from being hit by one bullet due to hitpoint radius system
        {
            // ignore this damage if it's a secondary selection (minor damage)
            if (_x > _newDamage) exitWith {
                _newDamage = 0;
            };

            // overwrite minor damage in secondary selections
            if (_x > 0) then {
                _cachedNewHitpointDamages set [_forEachIndex, 0];
                _cachedNewHitpointProjectiles set [_forEachIndex, ""];
            };
        } forEach _cachedNewHitpointDamages;

        if (_cachedNewHitpointDamages select _index < _newDamage) then {
            // apply these by the next matching hd call with selection "". If that one is not matching, this gets discarded
            _cachedNewHitpointDamages set [_index, _newDamage];
            _cachedNewHitpointProjectiles set [_index, _projectile];
        } else {
            // diag_log format["PREVENTED OVERWRITE: %1", [_newDamage, _projectile, _selection]];
        };
        _unit setVariable [QGVAR(cachedNewHitpointDamages), _cachedNewHitpointDamages];
        _unit setVariable [QGVAR(cachedNewHitpointProjectiles), _cachedNewHitpointProjectiles];
    };

    // use this to detect collision damage.
    if (_projectile == "") then {
        _unit setVariable [QGVAR(cachedLastCollisionDamage), _newDamage max (_unit getVariable [QGVAR(cachedLastCollisionDamage), 0])];
    };
};


diag_log text format ["HD %1 Retrun %2", _this, _damageReturn];


_damageReturn
