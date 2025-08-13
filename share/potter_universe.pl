:- discontiguous(data/2).
:- discontiguous(is_alive/2).
:- discontiguous(parent/2).
grandparent(X, Y) :- parent(X, Z), parent(Z, Y).
ancestor(X, Y) :- parent(X, Y).
ancestor(X, Y) :- parent(X, Z), ancestor(Z, Y).
sibling(X, Y) :- parent(Z, X), parent(Z, Y), X \= Y.
data(i0000, 'Potter, Harry James').
is_alive(i0000, 'True').
data(i0001, 'Potter, James').
is_alive(i0001, 'False').
data(i0002, 'Evans, Lily J').
is_alive(i0002, 'False').
data(i0003, 'Potter, Fleamont').
is_alive(i0003, 'False').
data(i0004, 'Potter, Euphemia').
is_alive(i0004, 'False').
data(i0005, 'Black, Orion').
is_alive(i0005, 'False').
data(i0006, 'Black, Walburga').
is_alive(i0006, 'False').
data(i0007, 'Black, Sirius III').
is_alive(i0007, 'False').
data(i0008, 'Black, Regulus Arcturus').
is_alive(i0008, 'False').
data(i0009, 'Black, Arcturus III').
is_alive(i0009, 'False').
data(i0010, 'Gamp, Hesper').
is_alive(i0010, 'False').
data(i0011, 'Macmillan, Melania').
is_alive(i0011, 'False').
data(i0012, 'Black, Lucretia').
is_alive(i0012, 'False').
data(i0013, 'Black, Sirius II').
is_alive(i0013, 'False').
data(i0014, 'Black, Lycoris').
is_alive(i0014, 'False').
data(i0015, 'Black, Regulus').
is_alive(i0015, 'False').
data(i0016, 'Black, Phineus Nigellus').
is_alive(i0016, 'False').
data(i0017, 'Flint, Ursula').
is_alive(i0017, 'False').
data(i0018, 'Black, Cygnus II').
is_alive(i0018, 'False').
data(i0019, 'Black, Belvina').
is_alive(i0019, 'False').
data(i0020, 'Black, Arcturus II').
is_alive(i0020, 'False').
data(i0022, 'Black, Sirius').
is_alive(i0022, 'False').
data(i0023, 'Black, Elladera').
is_alive(i0023, 'False').
data(i0024, 'Black, Iola').
is_alive(i0024, 'False').
data(i0025, 'Bulstrode, Violetta').
is_alive(i0025, 'False').
data(i0026, 'Black, Pollux').
is_alive(i0026, 'False').
data(i0027, 'Black, Cassiopeia').
is_alive(i0027, 'False').
data(i0028, 'Black, Dorea').
is_alive(i0028, 'False').
data(i0029, 'Black, Phineus').
is_alive(i0029, 'False').
data(i0030, 'Crabbe, Irma').
is_alive(i0030, 'False').
data(i0031, 'Black, Alphard').
is_alive(i0031, 'False').
data(i0032, 'Black, Cygnus III').
is_alive(i0032, 'False').
data(i0033, 'Rosier, Druella').
is_alive(i0033, 'True').
data(i0034, 'Black, Bellatrix').
is_alive(i0034, 'False').
data(i0035, 'Black, Andromeda').
is_alive(i0035, 'True').
data(i0036, 'Black, Narcissa').
is_alive(i0036, 'True').
data(i0037, 'Lestrange, Rodolphus').
is_alive(i0037, 'True').
data(i0038, 'Malfoy, Lucius Abraxas').
is_alive(i0038, 'True').
data(i0039, 'Malfoy, Draco Lucius').
is_alive(i0039, 'True').
data(i0040, 'Potter, Charlus').
is_alive(i0040, 'False').
data(i0041, 'Potter').
is_alive(i0041, 'True').
data(i0042, 'Burke, Herbert').
is_alive(i0042, 'False').
data(i0043, 'Burke').
is_alive(i0043, 'True').
data(i0044, 'Burke').
is_alive(i0044, 'True').
data(i0045, 'Burke').
is_alive(i0045, 'True').
data(i0046, 'Yaxley, Lysandra').
is_alive(i0046, 'False').
data(i0047, 'Black, Callidora').
is_alive(i0047, 'True').
data(i0048, 'Black, Charis').
is_alive(i0048, 'False').
data(i0049, 'Black, Cedrella').
is_alive(i0049, 'False').
data(i0050, 'Longbottom, Harfang').
is_alive(i0050, 'False').
data(i0051, 'Longbottom').
is_alive(i0051, 'True').
data(i0052, 'Longbottom').
is_alive(i0052, 'True').
data(i0053, 'Weasley, Septimus').
is_alive(i0053, 'False').
data(i0054, 'Crouch, Caspar').
is_alive(i0054, 'False').
data(i0055, 'Crouch').
is_alive(i0055, 'True').
data(i0056, 'Crouch').
is_alive(i0056, 'True').
data(i0057, 'Crouch').
is_alive(i0057, 'True').
data(i0058, 'Prewett, Ignatius').
is_alive(i0058, 'False').
data(i0059, 'Weasley, Arthur').
is_alive(i0059, 'True').
data(i0060, 'Lupin, Remus John').
is_alive(i0060, 'False').
data(i0061, 'Dumbledore, Albus Percival Wulfric Brian').
is_alive(i0061, 'False').
data(i0062, 'Prewett, Molly').
is_alive(i0062, 'True').
data(i0063, 'Granger, Hermione Jean').
is_alive(i0063, 'True').
data(i0064, 'Weasley, Ronald Bilius').
is_alive(i0064, 'True').
data(i0065, 'McGonagall, Minerva').
is_alive(i0065, 'True').
data(i0066, 'Longbottom, Frank').
is_alive(i0066, 'True').
data(i0067, 'Longbottom, Alice').
is_alive(i0067, 'True').
data(i0068, 'Longbottom, Neville').
is_alive(i0068, 'True').
data(i0069, 'Longbottom, Augusta').
is_alive(i0069, 'True').
data(i0070, 'Weasley, Ginevra Molly').
is_alive(i0070, 'True').
data(i0071, 'Weasley, Fred').
is_alive(i0071, 'False').
data(i0072, 'Weasley, George').
is_alive(i0072, 'True').
data(i0073, 'Weasley, William Arthur').
is_alive(i0073, 'True').
data(i0074, 'Weasley, Percy Ignatius').
is_alive(i0074, 'True').
data(i0075, 'Tonks, Edward').
is_alive(i0075, 'False').
data(i0076, 'Tonks, Nymphadora').
is_alive(i0076, 'False').
data(i0077, 'Snape, Severus').
is_alive(i0077, 'False').
data(i0078, 'Malfoy, Abraxas').
is_alive(i0078, 'False').
data(i0079, 'Hagrid, Rubeus').
is_alive(i0079, 'True').
data(i0080, 'Delacour, Fleur Isabelle').
is_alive(i0080, 'True').
data(i0081, 'Prewett, Fabian').
is_alive(i0081, 'True').
data(i0082, 'Prewett, Gideon').
is_alive(i0082, 'True').
data(i0083, 'Potter, Henry').
is_alive(i0083, 'False').
data(i0084, 'Fleamont').
is_alive(i0084, 'False').
data(i0087, 'Longbottom').
is_alive(i0087, 'True').
data(i0088, 'Longbottom').
is_alive(i0088, 'True').
data(i0089, 'Longbottom').
is_alive(i0089, 'True').
data(i0090, 'Longbottom, Enid').
is_alive(i0090, 'True').
data(i0091, 'Prewett').
is_alive(i0091, 'True').
data(i0092, 'Prewett').
is_alive(i0092, 'True').
data(i0093, 'Hitchens, Robert').
is_alive(i0093, 'False').
data(i0094, 'Black, Marius').
is_alive(i0094, 'False').
data(i0095, 'Weasley, Charlie').
is_alive(i0095, 'True').
data(i0096, 'Dursley, Vernon').
is_alive(i0096, 'True').
data(i0097, 'Evans, Petunia').
is_alive(i0097, 'True').
data(i0098, 'Dursley, Dudley').
is_alive(i0098, 'True').
data(i0099, 'Diggle, Dedalus').
is_alive(i0099, 'True').
data(i0100, 'Figg, Arabella Doreen').
is_alive(i0100, 'True').
data(i0101, 'Dursley, Marge').
is_alive(i0101, 'True').
data(i0102, 'Crockford, Doris').
is_alive(i0102, 'True').
data(i0103, 'Quirrell, Quirinus').
is_alive(i0103, 'False').
data(i0104, 'Malkin').
is_alive(i0104, 'True').
data(i0105, 'Ollivander, Garrick').
is_alive(i0105, 'True').
data(i0106, 'Crabbe, Vincent').
is_alive(i0106, 'False').
data(i0107, 'Goyle, Gregory').
is_alive(i0107, 'True').
data(i0108, 'Abbott, Hannah').
is_alive(i0108, 'True').
data(i0109, 'Black, Araminta Meliflua').
is_alive(i0109, 'True').
data(i0110, 'Lestrange, Rabastan').
is_alive(i0110, 'True').
data(i0111, 'Bones, Amelia Susan').
is_alive(i0111, 'True').
data(i0112, 'Umbridge, Dolores Jane').
is_alive(i0112, 'True').
data(i0113, 'Bones, Edgar').
is_alive(i0113, 'True').
data(i0114, 'Dumbledore, Aberforth').
is_alive(i0114, 'False').
data(i0115, 'Lovegood, Luna').
is_alive(i0115, 'True').
data(i0116, 'Abercrombie, Euan').
is_alive(i0116, 'True').
data(i0117, 'Zeller, Rose').
is_alive(i0117, 'True').
data(i0118, 'Marchbanks, Griselda').
is_alive(i0118, 'False').
data(i0119, 'Ogden, Tiberius').
is_alive(i0119, 'True').
data(i0120, 'Ryan, Barry').
is_alive(i0120, 'True').
data(i0121, 'Kirke, Andrew').
is_alive(i0121, 'True').
data(i0122, 'Sloper, Jack').
is_alive(i0122, 'True').
data(i0123, 'Derwent, Dilys').
is_alive(i0123, 'True').
data(i0124, 'Smethwyck, Hippocrates').
is_alive(i0124, 'True').
data(i0125, 'Pye, Augustus').
is_alive(i0125, 'True').
data(i0126, 'Rackharrow, Urquhart').
is_alive(i0126, 'False').
data(i0127, 'Widdershins, Willy').
is_alive(i0127, 'True').
data(i0128, 'Dolohov, Antonin').
is_alive(i0128, 'True').
data(i0129, 'Rockwood, Augustus').
is_alive(i0129, 'True').
data(i0130, 'Davies, Roger').
is_alive(i0130, 'True').
data(i0131, 'Edgecombe').
is_alive(i0131, 'True').
data(i0132, 'Edgecombe, Marietta').
is_alive(i0132, 'True').
data(i0133, 'Dawlish, John').
is_alive(i0133, 'True').
data(i0134, 'Bradley').
is_alive(i0134, 'True').
data(i0135, 'Chambers').
is_alive(i0135, 'True').
data(i0136, 'Tofty').
is_alive(i0136, 'True').
data(i0137, 'Jugson').
is_alive(i0137, 'True').
data(i0138, 'Mulciber').
is_alive(i0138, 'True').
data(i0139, 'Williamson').
is_alive(i0139, 'True').
data(i0140, 'Weasley').
is_alive(i0140, 'True').
data(i0141, 'Weasley').
is_alive(i0141, 'True').
data(i0142, 'Wildsmith, Ignatia').
is_alive(i0142, 'False').
data(i0143, 'Dodderidge, Daisy').
is_alive(i0143, 'False').
data(i0144, 'Hilliard, Robert').
is_alive(i0144, 'True').
data(i0145, 'Farley, Gemma').
is_alive(i0145, 'True').
data(i0146, 'Truman, Gabriel').
is_alive(i0146, 'True').
data(i0147, 'Black, Cygnus').
is_alive(i0147, 'False').
data(i0148, 'Max, Ella').
is_alive(i0148, 'False').
data(i0149, 'Black, Licorus').
is_alive(i0149, 'False').
data(i0150, 'Black, Misapinoa').
is_alive(i0150, 'False').
data(i0151, 'Black, Arcturus').
is_alive(i0151, 'False').
data(i0152, 'Tripe, Magenta').
is_alive(i0152, 'False').
data(i0153, 'Blishwick, Jimbo').
is_alive(i0153, 'False').
data(i0154, 'Bones, Susan').
is_alive(i0154, 'True').
data(i0155, 'Smith, Zacharias').
is_alive(i0155, 'True').
data(i0156, 'Hopkins, Wayne').
is_alive(i0156, 'True').
data(i0157, 'Finnigan').
is_alive(i0157, 'True').
data(i0158, 'Finnigan, Seamus').
is_alive(i0158, 'True').
data(i0159, 'Thomas, Dean').
is_alive(i0159, 'True').
data(i0160, 'Zabini, Blaize').
is_alive(i0160, 'True').
data(i0161, 'Nott, Theodore').
is_alive(i0161, 'True').
data(i0162, 'Boot, Terry').
is_alive(i0162, 'True').
data(i0163, 'Corner, Michael').
is_alive(i0163, 'True').
data(i0164, 'Cornfoot, Stephen').
is_alive(i0164, 'True').
data(i0165, 'Entwhistle, Kevin').
is_alive(i0165, 'True').
data(i0166, 'Goldstein, Anthony').
is_alive(i0166, 'True').
data(i0167, 'Finch-Fletchley, Justin').
is_alive(i0167, 'True').
data(i0168, 'Macmillan, Ernie').
is_alive(i0168, 'True').
data(i0169, 'Malone, Roger').
is_alive(i0169, 'True').
data(i0170, 'Rivers, Oliver').
is_alive(i0170, 'True').
data(i0171, 'Brocklehurst, Mandy').
is_alive(i0171, 'True').
data(i0172, 'Li, Sue').
is_alive(i0172, 'True').
data(i0173, 'MacDougal, Morag').
is_alive(i0173, 'True').
data(i0174, 'Patil, Padma').
is_alive(i0174, 'True').
data(i0175, 'Patil, Pavarti').
is_alive(i0175, 'True').
data(i0176, 'Turpin, Lisa').
is_alive(i0176, 'True').
data(i0177, 'Bulstrode, Millicent').
is_alive(i0177, 'True').
data(i0178, 'Davis, Tracey').
is_alive(i0178, 'True').
data(i0179, 'Greengrass, Daphne').
is_alive(i0179, 'True').
data(i0180, 'Greengrass, Astoria').
is_alive(i0180, 'True').
data(i0181, 'Parkinson, Pansy').
is_alive(i0181, 'True').
data(i0182, 'Runcorn, A.').
is_alive(i0182, 'True').
data(i0183, 'Jones, Megan').
is_alive(i0183, 'True').
data(i0184, 'Perks, Sally-Anne').
is_alive(i0184, 'True').
data(i0185, 'Brown, Lavender').
is_alive(i0185, 'True').
data(i0186, 'Moon, Lily').
is_alive(i0186, 'True').
data(i0187, 'Roper, Sophie').
is_alive(i0187, 'True').
data(i0188, 'Lovegood, Xenophilius').
is_alive(i0188, 'False').
data(i0189, 'Lovegood, Pandora').
is_alive(i0189, 'True').
data(i0190, 'of Stinchcombe, Linfred').
is_alive(i0190, 'False').
data(i0191, 'Potter, Hardwin').
is_alive(i0191, 'True').
data(i0192, 'Peverell, Iolanthe').
is_alive(i0192, 'True').
data(i0193, 'Fortescue, Florean').
is_alive(i0193, 'True').
data(i0194, 'Vector, Septima').
is_alive(i0194, 'True').
data(i0195, 'Babbling, Bathsheda').
is_alive(i0195, 'True').
data(i0196, 'Burbage, Charity').
is_alive(i0196, 'True').
data(i0197, 'Hooch, Rolanda').
is_alive(i0197, 'True').
data(i0198, 'Fudge, Cornelius Oswald').
is_alive(i0198, 'True').
data(i0199, 'Scrimgeour, Rufus').
is_alive(i0199, 'True').
data(i0200, 'Potter').
is_alive(i0200, 'True').
data(i0201, 'Potter').
is_alive(i0201, 'False').
data(i0202, 'Lupin, Lyall').
is_alive(i0202, 'True').
data(i0203, 'Howell, Hope').
is_alive(i0203, 'False').
data(i0204, 'Belby, Damocles').
is_alive(i0204, 'True').
data(i0205, 'Bones').
is_alive(i0205, 'False').
data(i0206, 'Bones').
is_alive(i0206, 'True').
data(i0207, 'Greengrass').
is_alive(i0207, 'False').
data(i0208, 'Greengrass').
is_alive(i0208, 'True').
data(i0209, 'Evans').
is_alive(i0209, 'True').
data(i0210, 'Greengrass, Gareth').
is_alive(i0210, 'False').
data(i0211, 'Fenwick, Benjy').
is_alive(i0211, 'True').
data(i0212, 'Scamander').
is_alive(i0212, 'False').
data(i0213, 'Scamander, Theseus').
is_alive(i0213, 'False').
data(i0214, 'Scamander, Newton Artemis Fido').
is_alive(i0214, 'False').
data(i0215, 'Lestrange').
is_alive(i0215, 'False').
data(i0216, 'Lestrange, Corvus').
is_alive(i0216, 'False').
data(i0217, 'Beaufort, Heloise').
is_alive(i0217, 'False').
data(i0218, 'Lestrange, Falco').
is_alive(i0218, 'False').
data(i0219, 'Lestrange, Corvus II').
is_alive(i0219, 'False').
data(i0220, 'Rosier, Minette').
is_alive(i0220, 'False').
data(i0221, 'Lestrange, Eglantine').
is_alive(i0221, 'False').
data(i0222, 'Volant, Salomé').
is_alive(i0222, 'False').
data(i0223, 'Lestrange, Leonie').
is_alive(i0223, 'False').
data(i0224, 'Lestrange, Manon').
is_alive(i0224, 'True').
data(i0225, 'Lestrange, Josette').
is_alive(i0225, 'True').
data(i0226, 'Lestrange, Corvus III').
is_alive(i0226, 'False').
data(i0227, 'Lestrange, Corvus IV').
is_alive(i0227, 'False').
data(i0228, 'Kama, Laurena').
is_alive(i0228, 'False').
data(i0229, 'Lestrange, Leta').
is_alive(i0229, 'False').
data(i0230, 'Tremblay, Bernard').
is_alive(i0230, 'False').
data(i0231, 'Tremblay, Clarisse').
is_alive(i0231, 'False').
data(i0232, 'Lestrange, Corvus V').
is_alive(i0232, 'False').
data(i0233, 'Lestrange').
is_alive(i0233, 'True').
data(i0234, 'Dursley').
is_alive(i0234, 'True').
data(i0235, 'Finnigan').
is_alive(i0235, 'True').
data(i0236, 'Lestrange, Cyrille').
is_alive(i0236, 'False').
data(i0237, 'Moreau, Darenne').
is_alive(i0237, 'False').
data(i0238, 'Lestrange, Cyrille II').
is_alive(i0238, 'True').
data(i0239, 'Lestrange, Fulcran').
is_alive(i0239, 'True').
data(i0240, 'Diggory, Cedric').
is_alive(i0240, 'False').
data(i0241, 'Diggory, Amos').
is_alive(i0241, 'True').
data(i0242, 'McGonagall, Robert').
is_alive(i0242, 'False').
data(i0243, 'Ross, Isobel').
is_alive(i0243, 'False').
data(i0244, 'McGonagall, Malcolm').
is_alive(i0244, 'True').
data(i0245, 'McGonagall, Robert Junior').
is_alive(i0245, 'True').
data(i0246, 'Slughorn, Horace Eugene Flaccus').
is_alive(i0246, 'True').
data(i0247, 'Riddle, Tom Marvolo').
is_alive(i0247, 'False').
data(i0248, 'Leach, Nobby').
is_alive(i0248, 'True').
data(i0249, 'Snape, Tobias').
is_alive(i0249, 'True').
data(i0250, 'Prince, Eileen').
is_alive(i0250, 'True').
data(i0251, 'Bungs, Rosalind Antigone').
is_alive(i0251, 'True').
data(i0252, 'Brookstanton, Rupert').
is_alive(i0252, 'True').
data(i0253, 'Trelawney, Sybill').
is_alive(i0253, 'False').
data(i0254, 'Elsrickle, Eldon').
is_alive(i0254, 'True').
data(i0255, 'Hobart, Jarleth').
is_alive(i0255, 'True').
data(i0256, 'Lügner, Garvin').
is_alive(i0256, 'True').
data(i0257, 'Blay, Blagdon').
is_alive(i0257, 'True').
data(i0258, 'Grymm, Malodora').
is_alive(i0258, 'True').
data(i0259, 'Black, Eduardus Limette').
is_alive(i0259, 'False').
data(i0260, 'Grindelwald, Gellert').
is_alive(i0260, 'False').
data(i0261, 'Dumbledore, Kendra').
is_alive(i0261, 'False').
data(i0262, 'Dumbledore, Percival').
is_alive(i0262, 'False').
data(i0263, 'Dumbledore, Ariana').
is_alive(i0263, 'False').
data(i0264, 'Sprout, Pomona').
is_alive(i0264, 'True').
data(i0265, 'Urquart, Elphinstone').
is_alive(i0265, 'True').
data(i0266, 'Jones, Gwenog').
is_alive(i0266, 'True').
data(i0267, 'Egg, Mordicus').
is_alive(i0267, 'True').
data(i0268, 'Nott, Cantankerus').
is_alive(i0268, 'True').
data(i0269, 'Gryffindor, Godric').
is_alive(i0269, 'True').
data(i0270, 'Kettleburn, Silvanus').
is_alive(i0270, 'True').
data(i0271, 'Gaunt, Gormlaith').
is_alive(i0271, 'True').
data(i0272, 'Borage, Libatius').
is_alive(i0272, 'True').
data(i0273, 'Tutley, Adrian').
is_alive(i0273, 'True').
data(i0274, 'Umbridge, Orford').
is_alive(i0274, 'True').
data(i0275, 'Cracknell, Ellen').
is_alive(i0275, 'True').
data(i0276, 'Scamander, Rolf').
is_alive(i0276, 'True').
data(i0277, 'Pettigrew, Peter').
is_alive(i0277, 'True').
data(i0278, 'Shacklebolt, Kingsley').
is_alive(i0278, 'True').
data(i0279, 'Pomfrey, Poppy').
is_alive(i0279, 'True').
data(i0280, 'Bagnold, Millicent').
is_alive(i0280, 'True').
data(i0281, 'Dearborn, Caradoc').
is_alive(i0281, 'True').
data(i0282, 'MkKinnon, Marlene').
is_alive(i0282, 'True').
data(i0283, 'Vance, Emmeline').
is_alive(i0283, 'True').
data(i0284, 'Doge, Elphias').
is_alive(i0284, 'True').
data(i0285, 'Meadowes, Dorcas').
is_alive(i0285, 'True').
data(i0286, 'Chang, Cho').
is_alive(i0286, 'True').
data(i0287, 'Spinnet, Alicia').
is_alive(i0287, 'True').
data(i0288, 'Flint, Marcus').
is_alive(i0288, 'True').
data(i0289, 'Creevey, Colin').
is_alive(i0289, 'True').
data(i0290, 'Monkstanley, Levina').
is_alive(i0290, 'False').
data(i0291, 'Delacour, Gabrielle').
is_alive(i0291, 'True').
data(i0292, 'Patil').
is_alive(i0292, 'True').
data(i0293, 'Flitwick, Filus').
is_alive(i0293, 'True').
data(i0294, 'Goldstein, Queenie').
is_alive(i0294, 'False').
data(i0295, 'Lupin, Edward Remus').
is_alive(i0295, 'True').
data(i0296, 'McLaggen, Cormac').
is_alive(i0296, 'True').
data(i0298, 'Nuttley, Orabella').
is_alive(i0298, 'True').
data(i0299, 'Slytherin, Salazar').
is_alive(i0299, 'False').
data(i0300, 'Skeeter, Rita').
is_alive(i0300, 'True').
data(i0301, 'Binns, Cuthbert').
is_alive(i0301, 'True').
data(i0302, 'Lockhart, Gilderoy').
is_alive(i0302, 'True').
data(i0303, 'Riddle').
is_alive(i0303, 'False').
data(i0304, 'Gaunt, Merope').
is_alive(i0304, 'False').
data(i0305, 'Gaunt, Marvolo').
is_alive(i0305, 'False').
data(i0306, 'Gaunt, Morfin').
is_alive(i0306, 'False').
data(i0307, 'Bole, Lucian').
is_alive(i0307, 'True').
data(i0308, 'Derrick, Peregrine').
is_alive(i0308, 'True').
data(i0309, 'Dunn, Elora').
is_alive(i0309, 'True').
data(i0310, 'Haywood, Beatrice').
is_alive(i0310, 'True').
data(i0311, 'Clearwater, Penelope').
is_alive(i0311, 'True').
data(i0312, 'Wood, Oliver').
is_alive(i0312, 'True').
data(i0313, 'Johnson, Angelina').
is_alive(i0313, 'True').
data(i0314, 'Jordan, Lee').
is_alive(i0314, 'True').
data(i0315, 'Stimpson, Patricia').
is_alive(i0315, 'True').
data(i0316, 'Towler, Kenneth').
is_alive(i0316, 'True').
data(i0317, ', Leanne').
is_alive(i0317, 'True').
data(i0318, 'Belby, Marcus').
is_alive(i0318, 'True').
data(i0319, 'Bell, Katie').
is_alive(i0319, 'True').
data(i0320, 'Carmichael').
is_alive(i0320, 'True').
data(i0321, 'Fawcett').
is_alive(i0321, 'True').
data(i0322, 'Stebbins').
is_alive(i0322, 'True').
data(i0323, 'Summers').
is_alive(i0323, 'True').
data(i0324, 'Harper').
is_alive(i0324, 'True').
data(i0325, 'Vane, Romilda').
is_alive(i0325, 'True').
data(i0326, 'Ackerley, Stewart').
is_alive(i0326, 'True').
data(i0327, 'Baddock, Malcolm').
is_alive(i0327, 'True').
data(i0328, 'Branstone, Malcolm').
is_alive(i0328, 'True').
data(i0329, 'Cauldwell, Owen').
is_alive(i0329, 'True').
data(i0330, 'Creevey, Dennis').
is_alive(i0330, 'True').
data(i0331, 'Dobbs, Emma').
is_alive(i0331, 'True').
data(i0332, 'MacDonald, Natalie').
is_alive(i0332, 'True').
data(i0333, 'Madley, Laura').
is_alive(i0333, 'True').
data(i0334, 'Pritchard, Graham').
is_alive(i0334, 'True').
data(i0335, 'Peaks, James').
is_alive(i0335, 'True').
data(i0336, 'Quirke, Orla').
is_alive(i0336, 'True').
data(i0337, 'Whitby, Kevin').
is_alive(i0337, 'True').
data(i0338, 'Wolpert, Nigel').
is_alive(i0338, 'True').
data(i0339, ', Alys').
is_alive(i0339, 'True').
data(i0340, 'Midgen, Eloise').
is_alive(i0340, 'True').
data(i0341, 'Montague, Graham').
is_alive(i0341, 'True').
data(i0342, 'Robins, Demelza').
is_alive(i0342, 'True').
data(i0343, ', Nagini').
is_alive(i0343, 'False').
data(i0344, 'Moody, Alastor').
is_alive(i0344, 'True').
data(i0345, 'Goshawk, Miranda').
is_alive(i0345, 'True').
data(i0346, 'Greyback, Fenrir').
is_alive(i0346, 'True').
data(i0347, 'Hufflepuff, Helga').
is_alive(i0347, 'True').
data(i0348, 'Cresswell, Dirk').
is_alive(i0348, 'True').
data(i0349, 'Potter, Ralston').
is_alive(i0349, 'False').
data(i0350, 'Radford, Mnemone').
is_alive(i0350, 'False').
data(i0351, 'Malfoy, Armand').
is_alive(i0351, 'False').
data(i0352, 'Mimsy-Porpington, Nicholas').
is_alive(i0352, 'False').
data(i0353, 'Fawley, Hector').
is_alive(i0353, 'True').
data(i0354, 'Gamp, Ulick').
is_alive(i0354, 'True').
data(i0355, 'Rowle, Damocles').
is_alive(i0355, 'True').
data(i0356, 'Parkinson, Perseus').
is_alive(i0356, 'True').
data(i0357, 'Diggory, Eldritch').
is_alive(i0357, 'True').
data(i0358, 'Boot, Albert').
is_alive(i0358, 'True').
data(i0359, 'Flack, Basil').
is_alive(i0359, 'True').
parent(i0002, i0000).
parent(i0001, i0000).
parent(i0004, i0001).
parent(i0003, i0001).
parent(i0006, i0007).
parent(i0006, i0008).
parent(i0005, i0007).
parent(i0005, i0008).
parent(i0011, i0005).
parent(i0011, i0012).
parent(i0009, i0005).
parent(i0009, i0012).
parent(i0010, i0009).
parent(i0010, i0014).
parent(i0010, i0015).
parent(i0013, i0009).
parent(i0013, i0014).
parent(i0013, i0015).
parent(i0017, i0013).
parent(i0017, i0018).
parent(i0017, i0019).
parent(i0017, i0020).
parent(i0017, i0029).
parent(i0016, i0013).
parent(i0016, i0018).
parent(i0016, i0019).
parent(i0016, i0020).
parent(i0016, i0029).
parent(i0025, i0026).
parent(i0025, i0027).
parent(i0025, i0028).
parent(i0025, i0094).
parent(i0018, i0026).
parent(i0018, i0027).
parent(i0018, i0028).
parent(i0018, i0094).
parent(i0030, i0006).
parent(i0030, i0031).
parent(i0030, i0032).
parent(i0026, i0006).
parent(i0026, i0031).
parent(i0026, i0032).
parent(i0033, i0034).
parent(i0033, i0035).
parent(i0033, i0036).
parent(i0032, i0034).
parent(i0032, i0035).
parent(i0032, i0036).
parent(i0036, i0039).
parent(i0038, i0039).
parent(i0028, i0041).
parent(i0040, i0041).
parent(i0019, i0043).
parent(i0019, i0044).
parent(i0019, i0045).
parent(i0042, i0043).
parent(i0042, i0044).
parent(i0042, i0045).
parent(i0046, i0047).
parent(i0046, i0048).
parent(i0046, i0049).
parent(i0020, i0047).
parent(i0020, i0048).
parent(i0020, i0049).
parent(i0047, i0051).
parent(i0047, i0052).
parent(i0050, i0051).
parent(i0050, i0052).
parent(i0049, i0059).
parent(i0049, i0140).
parent(i0049, i0141).
parent(i0053, i0059).
parent(i0053, i0140).
parent(i0053, i0141).
parent(i0048, i0055).
parent(i0048, i0056).
parent(i0048, i0057).
parent(i0054, i0055).
parent(i0054, i0056).
parent(i0054, i0057).
parent(i0062, i0064).
parent(i0062, i0070).
parent(i0062, i0071).
parent(i0062, i0072).
parent(i0062, i0073).
parent(i0062, i0074).
parent(i0062, i0095).
parent(i0059, i0064).
parent(i0059, i0070).
parent(i0059, i0071).
parent(i0059, i0072).
parent(i0059, i0073).
parent(i0059, i0074).
parent(i0059, i0095).
parent(i0067, i0068).
parent(i0066, i0068).
parent(i0069, i0066).
parent(i0087, i0066).
parent(i0035, i0076).
parent(i0075, i0076).
parent(i0078, i0038).
parent(i0091, i0062).
parent(i0091, i0081).
parent(i0091, i0082).
parent(i0083, i0003).
parent(i0084, i0083).
parent(i0084, i0200).
parent(i0201, i0083).
parent(i0201, i0200).
parent(i0088, i0087).
parent(i0088, i0050).
parent(i0088, i0089).
parent(i0092, i0091).
parent(i0092, i0058).
parent(i0076, i0295).
parent(i0060, i0295).
parent(i0097, i0098).
parent(i0097, i0000).
parent(i0096, i0098).
parent(i0096, i0000).
parent(i0234, i0096).
parent(i0234, i0101).
parent(i0131, i0132).
parent(i0148, i0022).
parent(i0148, i0016).
parent(i0148, i0023).
parent(i0148, i0024).
parent(i0147, i0022).
parent(i0147, i0016).
parent(i0147, i0023).
parent(i0147, i0024).
parent(i0152, i0147).
parent(i0152, i0150).
parent(i0152, i0151).
parent(i0149, i0147).
parent(i0149, i0150).
parent(i0149, i0151).
parent(i0027, i0109).
parent(i0157, i0158).
parent(i0235, i0158).
parent(i0292, i0174).
parent(i0292, i0175).
parent(i0207, i0179).
parent(i0207, i0180).
parent(i0189, i0115).
parent(i0188, i0115).
parent(i0190, i0191).
parent(i0200, i0040).
parent(i0203, i0060).
parent(i0202, i0060).
parent(i0205, i0111).
parent(i0205, i0113).
parent(i0205, i0206).
parent(i0206, i0154).
parent(i0208, i0207).
parent(i0208, i0210).
parent(i0209, i0002).
parent(i0209, i0097).
parent(i0211, i0159).
parent(i0212, i0213).
parent(i0212, i0214).
parent(i0215, i0216).
parent(i0215, i0236).
parent(i0217, i0219).
parent(i0217, i0218).
parent(i0216, i0219).
parent(i0216, i0218).
parent(i0222, i0221).
parent(i0222, i0223).
parent(i0218, i0221).
parent(i0218, i0223).
parent(i0220, i0224).
parent(i0220, i0225).
parent(i0220, i0226).
parent(i0219, i0224).
parent(i0219, i0225).
parent(i0219, i0226).
parent(i0221, i0227).
parent(i0226, i0227).
parent(i0228, i0229).
parent(i0227, i0229).
parent(i0223, i0231).
parent(i0230, i0231).
parent(i0231, i0232).
parent(i0227, i0232).
parent(i0233, i0110).
parent(i0233, i0037).
parent(i0237, i0238).
parent(i0237, i0239).
parent(i0236, i0238).
parent(i0236, i0239).
parent(i0241, i0240).
parent(i0243, i0065).
parent(i0243, i0244).
parent(i0243, i0245).
parent(i0242, i0065).
parent(i0242, i0244).
parent(i0242, i0245).
parent(i0250, i0077).
parent(i0249, i0077).
parent(i0261, i0061).
parent(i0261, i0114).
parent(i0261, i0263).
parent(i0262, i0061).
parent(i0262, i0114).
parent(i0262, i0263).
parent(i0275, i0112).
parent(i0274, i0112).
parent(i0304, i0247).
parent(i0303, i0247).
parent(i0305, i0304).
parent(i0305, i0306).
