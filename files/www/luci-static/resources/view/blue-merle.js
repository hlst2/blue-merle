'use strict';
'require view';
'require fs';
'require ui';
'require rpc';

var css = '								\
	.controls {							\
		display: flex;					\
		margin: .5em 0 1em 0;			\
		flex-wrap: wrap;				\
		justify-content: space-around;	\
	}									\
										\
	.controls > * {						\
		padding: .25em;					\
		white-space: nowrap;			\
		flex: 1 1 33%;					\
		box-sizing: border-box;			\
		display: flex;					\
		flex-wrap: wrap;				\
	}									\
										\
	.controls > *:first-child,			\
	.controls > * > label {				\
		flex-basis: 100%;				\
		min-width: 250px;				\
	}									\
										\
	.controls > *:nth-child(2),			\
	.controls > *:nth-child(3) {		\
		flex-basis: 20%;				\
	}									\
										\
	.controls > * > .btn {				\
		flex-basis: 20px;				\
		text-align: center;				\
	}									\
										\
	.controls > * > * {					\
		flex-grow: 1;					\
		align-self: center;				\
	}									\
										\
	.controls > div > input {			\
		width: auto;					\
	}									\
';

var isReadonlyView = !L.hasViewPermission() || null;


function callBlueMerle(arg, slot) {
    const cmd = "/usr/libexec/blue-merle";
    const args = slot ? [arg, String(slot)] : [arg];
    var prom = fs.exec(cmd, args);
    return prom.then(
        function(res) {
            if (res.code != 0) {
                throw new Error("Return code " + res.code);
            }
            return res.stdout;
        }
    );
}

function readIMEI(slot) { return callBlueMerle("read-imei", slot); }
function readIMSI(slot) { return callBlueMerle("read-imsi", slot); }
function readSlot()     { return callBlueMerle("read-slot"); }

function handleShutdown(ev) {
    return callBlueMerle("shutdown");
}

function handleSimSwap(slot) {
    return function(ev) {
        const spinnerID = 'swap-spinner-id';
        var dlg = ui.showModal(_('Starting SIM swap on slot %s...').format(slot),
            [
                E('p', { 'class': 'spinning', 'id': spinnerID },
                    _('Shutting down modem…')
                 )
            ]
        );
        callBlueMerle("shutdown-modem", slot).then(
            function(res) {
                dlg.appendChild(E('pre', { 'class': 'result' }, res));
                dlg.appendChild(E('p', { 'class': 'text' }, _("Generating Random IMEI")));
                callBlueMerle("random-imei", slot).then(
                    function(res) {
                        document.getElementById(spinnerID).style = "display:none";
                        dlg.appendChild(
                            E('div', { 'class': 'text' }, [
                                E('p', { 'class': 'text' },
                                    _("New IMEI on slot %s:").format(slot) + " " + res),
                                E('p', { 'class': 'text' },
                                    _("Please shutdown the device, swap the SIM, then go to another place before booting")),
                                E('button', {
                                    'class': 'btn cbi-button-positive',
                                    'click': handleShutdown,
                                    'disabled': isReadonlyView
                                }, [ _('Shutdown…') ])
                            ])
                        );
                    }
                ).catch(function(err) {
                    dlg.appendChild(E('p', { 'class': 'error' }, _('Error setting IMEI! ') + err));
                });
            }
        ).catch(function(err) {
            dlg.appendChild(E('p', { 'class': 'error' }, _('Error! ') + err));
        });
    };
}

function buildSlotRow(slot) {
    const imeiInputID = 'imei-input-' + slot;
    const imsiInputID = 'imsi-input-' + slot;

    const row = E('div', { 'class': 'cbi-section' }, [
        E('h3', {}, _('SIM Slot %s').format(slot)),
        E('div', { 'class': 'controls' }, [
            E('div', {}, [
                E('label', {}, _('IMEI') + ':'),
                E('span', { 'class': 'control-group' }, [
                    E('input', {
                        'id': imeiInputID, 'type': 'text', 'placeholder': _('reading…'),
                        'disabled': true
                    })
                ])
            ]),
            E('div', {}, [
                E('label', {}, _('IMSI') + ':'),
                E('span', { 'class': 'control-group' }, [
                    E('input', {
                        'id': imsiInputID, 'type': 'text', 'placeholder': _('reading…'),
                        'disabled': true
                    })
                ])
            ])
        ]),
        E('div', {}, [
            E('label', {}, _('Actions') + ':'), ' ',
            E('span', { 'class': 'control-group' }, [
                E('button', {
                    'class': 'btn cbi-button-positive',
                    'click': handleSimSwap(slot),
                    'disabled': isReadonlyView
                }, [ _('SIM swap on slot %s…').format(slot) ])
            ])
        ])
    ]);

    readIMEI(slot).then(function(imei) {
        document.getElementById(imeiInputID).value = imei;
    }).catch(function(err) {
        document.getElementById(imeiInputID).value = _('error');
    });

    readIMSI(slot).then(function(imsi) {
        document.getElementById(imsiInputID).value = imsi;
    }).catch(function(err) {
        document.getElementById(imsiInputID).value = _('No IMSI found');
    });

    return row;
}


return view.extend({
    load: function() {
        return readSlot().catch(function() { return '1'; });
    },

    render: function(activeSlot) {
        var view = E([], [
            E('style', { 'type': 'text/css' }, [ css ]),
            E('h2', {}, _('Blue Merle')),
            E('p', {}, _('Mudi 7 (GL-E5800) — Qualcomm Snapdragon X72 (Dragonwing MBB Gen 3) modem.')),
            E('p', {}, _('Currently active SIM slot: %s').format(activeSlot)),
            buildSlotRow(1),
            buildSlotRow(2)
        ]);
        return view;
    },

    handleSave: null,
    handleSaveApply: null,
    handleReset: null
});
