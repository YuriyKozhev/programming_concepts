local ex1 = {a = 3, b = 5; c = 7, function (x) return x end}
print(ex1.new_key) -- nil
setmetatable(ex1, { __index = {new_key = 2} })
print(ex1.new_key) -- 2


local ex2 = {3, 5, 7, function (x) print(x) end}
setmetatable(ex2, {__index = function (self, attr)
    self.attr = self[1] * attr
    return self.attr
end})
print(ex2[10]) -- 3 * 10 = 30


KindOfClass = {
    new = function(cls, value)
        local instance = {value = value}
        setmetatable(instance, {__index = cls})
        return instance
    end;
}
function KindOfClass:display()
    print(self.value)
end;
local kind_of_instance = KindOfClass:new(2)
kind_of_instance.display(kind_of_instance) -- 2
kind_of_instance:display() -- 2
KindOfClass:display() -- nil

KindOfClassChild = {
    update = function (self, new_value)
        self.value = new_value
    end
}
setmetatable(KindOfClassChild, {__index = KindOfClass})
local kind_of_instance_child = KindOfClassChild:new(2)
kind_of_instance_child:update(3)
kind_of_instance_child:display() -- 3


IncrementClass = {
    increment = function (self)
        self.value = self.value + 1
    end
}
DecrementClass = {
    decrement = function (self)
        self.value = self.value  - 1
    end
}
function TrivialMethodResolutionOrder(parent_classes, attr)
    for _, parent_class in ipairs(parent_classes) do
        local found_attr = parent_class[attr]
        if found_attr then return found_attr end
    end
end
--[[
     ClassA
    /      \
ClassB   ClassC
    \      /
     ClassD

ClassD -> ClassB -> ClassA -> ClassC
--]]
function CreateInheretedClass(new_class, ...)
    new_class._parent_classes = {...}
    setmetatable(new_class, {__index = function(cls, attr)
        return TrivialMethodResolutionOrder(cls._parent_classes, attr)
    end})
    return new_class
end
InheretedClass = CreateInheretedClass({
    init = function(cls, value)
        local instance = {value = value}
        setmetatable(instance, {__index = cls})
        return instance
    end;
}, IncrementClass, DecrementClass)
getmetatable(InheretedClass).__call = InheretedClass.init
local inhereted_class_instance = InheretedClass(5)
inhereted_class_instance:increment()
inhereted_class_instance:increment()
inhereted_class_instance:decrement()
print(inhereted_class_instance.value)

getmetatable(inhereted_class_instance).__tostring = function (self) return type(self)  end
print(inhereted_class_instance) -- table

------------
print('---')
------------

ClassObject = {
    __init__ = function(self)
        assert(self ~= nil and self._cf_instance)
    end;
    _cf_class = true;
    _cf_parent_classes = {};
    _cf_methods = {};
}
ClassFactory = {
    get_class_element = function (cls, _class, element_name, indexed)
        assert(_class ~= nil and _class._cf_class)
        assert(element_name ~= nil and type(element_name) == "string")
        assert(indexed == nil or type(indexed) == "boolean")

        if indexed then
            return _class[element_name]
        end

        for attr_name, attr_value in pairs(_class) do
            if attr_name == element_name then
                return attr_value
            end
        end
    end;

    get_class_method = function (cls, _class, method_name, indexed)
        assert(_class ~= nil and _class._cf_class)
        assert(method_name ~= nil and type(method_name) == "string")
        assert(indexed == nil or type(indexed) == "boolean")
        

        local value = cls:get_class_element(_class, method_name, indexed)
        if type(value) == "function" then
            return value
        end
    end;

    get_class_attribute = function (cls, _class, attribute_name, indexed)
        assert(_class ~= nil and _class._cf_class)
        assert(attribute_name ~= nil and type(attribute_name) == "string")
        assert(indexed == nil or type(indexed) == "boolean")

        local value = cls:get_class_element(_class, attribute_name, indexed)
        if type(value) ~= "function" then
            return value
        end
    end;

    generate_class_index = function (cls)
        return function(_class, attr)
            assert(_class ~= nil and _class._cf_class)
            return TrivialMethodResolutionOrder(_class._cf_parent_classes, attr)
        end
    end;

    generate_isinstance_method = function(cls)
        return function (self, _check_class, current_class)
            assert(self ~= nil and self._cf_instance)
            assert(_check_class ~= nil and _check_class._cf_class)
            assert(current_class == nil or current_class._cf_class)

            current_class = current_class or self._cf_instance_class

            if current_class == _check_class then
                return true
            end

            for _, parent in ipairs(current_class._cf_parent_classes) do
                if self:isinstance(_check_class, parent) then
                    return true
                end
            end
            return false
        end
    end;

    generate_super_method = function(cls)
        return function (_class)
            assert(_class ~= nil and _class._cf_class)

            return _class._cf_parent_classes[1]
        end
    end;

    generate_class_constructor = function (cls)
        return function (_class, ...)
            assert(_class ~= nil and _class._cf_class)

            local instance = {
                _cf_instance = true,
                _cf_instance_class = _class,
            }
            local instance_meta = {
                __index = _class,
                __tostring = _class.__str__
            }
            setmetatable(instance, instance_meta)

            _class.__init__(instance, ...)
            assert(instance._cf_instance and instance._cf_instance_class == _class)
            
            return instance
        end
    end;

    generate_class_register_method = function (cls)
        return function (_class, name, method)
            assert(_class ~= nil and _class._cf_class)
            assert(type(name) == 'string')
            assert(type(method) == 'function')
            
            if name:find('^_cf') ~= nil then
                return
            end
            
            _class._cf_methods[name] = method

            _class[name] = function (self, ...)
                assert(self ~= nil and self._cf_instance and self:isinstance(_class))
                return method(self, ...)
            end
        end
    end;

    generate_class_unregister_method = function (cls)
        return function (_class, name)
            assert(_class ~= nil and _class._cf_class)
            assert(type(name) == 'string')
            assert(name:find('^_cf') == nil)

            local method = _class._cf_methods[name]
            assert(method ~= nil)

            _class._cf_methods[name] = nil
            _class[name] = method
        end
    end;

    create_new_class = function (cls, _class, ...)
        assert(_class ~= nil)

        local parent_classes = {...}
        for _, parent_class in ipairs(parent_classes) do
            if not parent_class._cf_class then
                error('ClassFactory tried to create a class with incorrect parent')
            end
        end
        table.insert(parent_classes, ClassObject)

        _class._cf_class = true

        _class._cf_methods = {};
        _class.register_method = cls:generate_class_register_method()
        for attr_name, attr_value in pairs(_class) do
            if type(attr_value) == "function" and attr_name ~= 'register_method' then
                _class:register_method(attr_name, attr_value)
            end
        end
        _class.unregister_method = cls:generate_class_unregister_method()
        _class.make_method_static = _class.unregister_method

        _class._cf_parent_classes = parent_classes
        local _class_meta = {
            __index = cls:generate_class_index()
        }
        setmetatable(_class, _class_meta)
        
        if cls:get_class_method(_class, '__init__', true) == nil then
            error('ClassFactory tried to create a class constructor without __init__ method')
        end
        _class_meta.__call = cls:generate_class_constructor();
        
        _class.isinstance = cls:generate_isinstance_method()
        _class.super = cls:generate_super_method()

        setmetatable(_class, _class_meta)
        return _class
    end;

    override = function(...)
        error("method should be overridden")
    end;
}
setmetatable(ClassFactory, {
    __call = function (cls, _class, ...)
        return cls:create_new_class(_class, ...)
    end;
})

Empty = ClassFactory({})
Point = ClassFactory({
    __init__ = function(self, x, y)
        self.x = x or 1
        self.y = y or 2
    end;
}, Empty)
PrintablePoint = ClassFactory({
    __str__ = function (self)
        return '(' .. self.x .. ', ' .. self.y .. ')'
    end;
}, Point)
CalculatedPoint = ClassFactory({
    distance = function (self, c, method)
        if c then
            return c * math.sqrt(self.x^2  + self.y^2)
        end
        return math.sqrt(self.x^2  + self.y^2)
    end;
}, Point)
PrintableCalculatedPoint = ClassFactory({
    increment_number = function (number)
        return number + 1
    end;
}, PrintablePoint, CalculatedPoint)
PrintableCalculatedPoint:make_method_static('increment_number')
local p1 = PrintableCalculatedPoint(nil, 3)
print(p1)
print(p1:distance(10))
print(p1.increment_number(10))
assert(
    p1:isinstance(PrintableCalculatedPoint) 
    and p1:isinstance(PrintablePoint) 
    and p1:isinstance(CalculatedPoint) 
    and p1:isinstance(ClassObject)
)

------------
print('---\nTask 3\n---')
------------

math.randomseed(42)

local function roll_dice(probability)
    return math.random() < probability
end

get_random_obj = function (obj, level)
    level = level or 2
    if level == 0 then
        return obj
    end

    local keyset={}
    local n=0
    for k,v in pairs(obj) do
        n=n+1
        keyset[n]=k
    end

    local chosen_key = keyset[math.random(n)]
    return get_random_obj(obj[chosen_key], level-1)
end

DeltaState = ClassFactory({
    __init__ = function (self, default_value)
        self.health_delta = default_value or 0
        self.money_delta = default_value or 0
        self.satisfaction_delta = default_value or 0
    end;

    __str__ = function (self)
        return 'DeltaState(health_delta='..self.health_delta..',money_delta='..self.money_delta..',satisfaction_delta='..self.satisfaction_delta..')'
    end;

    apply = function (self, durlyandets)
        durlyandets.health = durlyandets.health + self.health_delta
        durlyandets.money = durlyandets.money + self.money_delta
        durlyandets.satisfaction = durlyandets.satisfaction + self.satisfaction_delta
    end
})
Change = ClassFactory({
    __init__ = function (self, update)
        self.update = update or self.default_update;
    end;

    default_update = function(_self, delta_state) end;

    apply = function (self, delta_state)
        self:update(delta_state)
    end;

    chain = function (self, next_change)
        local curr_update = self.update
        self.update = function(_self, delta_state)
            curr_update(_self, delta_state)
            next_change:update(delta_state)
        end
        return self
    end;
})
Change(function(self, ds) ds.health_delta = ds.health_delta - 1 end):chain(
    Change(function(self, ds) ds.health_delta = ds.health_delta + 4 end)
):apply(DeltaState())


Location = ClassFactory({
    __init__ = function (self, animals)
        self.animals = animals or {slesandra = 0, sisyandra = 0, chuchundra = 0}
    end;

    affect_zumbalstvo = function (self, context)
        context.change:chain(Change(function(_self, d)
            d.money_delta = d.money_delta + 2 * self.animals.slesandra
        end))
    end;

    affect_gulbonstvo = function (self, context)
        context.change:chain(Change(function(_self, d)
            d.satisfaction_delta = d.satisfaction_delta + 2 * self.animals.sisyandra
        end))
    end;
    
    affect_shlyamsanye = function (self, context)
        context.change:chain(Change(function(_self, d)
            d.health_delta = d.health_delta + 2 * self.animals.chuchundra
        end))
    end;

    affect_general = function (self, context)
        return
    end;
})

Workland = ClassFactory({
    __init__  = function (self, ...)
        Workland:super().__init__(self, ...)
        self.animals = {slesandra = 3, chuchundra = 1, sisyandra = 1}
    end;
}, Location)
Balbesburg = ClassFactory({
    -- Балбесбург
    -- С вероятноятью 0.15 каждая слесандра может нанести ущерб здоровью в размере 0.1 единицы
    affect_general = function (self, context)
        context.change:chain(Change(function(_self, ds)
            if roll_dice(0.15) then
                ds.health_delta = ds.health_delta - 0.1 * self.animals.slesandra
            end
        end))
    end;

    __str__ = function (self)
        return 'Workland, Balbesburg'
    end;
}, Workland)
Dolbesburg = ClassFactory({
    -- Долбесбург
    -- Добавляет 20 процентов к производительности слесандр, 
    -- но забирает на 30 процентов больше удовлетворенности
    affect_zumbalstvo = function (self, context)
        context.change:chain(Change(function(_self, ds)
            ds.money_delta = ds.money_delta + 2 * 1.2 * self.animals.slesandra
            ds.satisfaction_delta = ds.satisfaction_delta * 1.3
        end))
    end;

    affect_shlyamsanye = function (self, context)
        context.change:chain(Change(function(_self, ds)
            ds.satisfaction_delta = ds.satisfaction_delta * 1.3
        end))
    end;

    __str__ = function (self)
        return 'Workland, Dolbesburg'
    end;
}, Workland)

Beachland = ClassFactory({
    __init__  = function (self, ...)
        Beachland:super().__init__(self, ...)
        self.animals = {slesandra = 1, chuchundra = 1, sisyandra = 3}
    end
}, Location)
Kuramariby = ClassFactory({
    --  Каждая сисяндра перестает работать с вероятностью 0.7 во втором 
    -- и последующих интервалах нахождения в локации
    affect_gulbonstvo = function (self, context)
        if context.previous_areas[1] == Kuramariby then
            if roll_dice(0.3) then
                Kuramariby:super().affect_gulbonstvo(self, context)
            end
        else
            Kuramariby:super().affect_gulbonstvo(self, context)
        end
    end;

    __str__ = function (self)
        return 'Beachland, Kuramariby'
    end;
}, Beachland)
PuntaPelikana = ClassFactory({
    -- Начиная со 2 интервала нахождения в локации, 
    -- сисяндры генерируют на 23 процента больше удовлетворенности, 
    -- но с вероятностью 0.2 списывается 50% всех денег
    affect_gulbonstvo = function (self, context)
        if context.previous_areas[1] == PuntaPelikana then
            context.change:chain(Change(function(_self, ds)
                ds.satisfaction_delta = ds.satisfaction_delta + 1.23 * #self.get_animals(Sisyandra)
            end))
            if roll_dice(0.2) then
                context.change:chain(Change(function(_self, ds)
                    context.durlyandets.money = 0.5 * (context.durlyandets.money + ds.money_delta)
                    ds.money_delta = 0
                end))
            end
        else
            PuntaPelikana:super().affect_gulbonstvo(self, context)
        end
    end;

    __str__ = function (self)
        return 'Beachland, PuntaPelikana'
    end;
}, Beachland)

Pranaland = ClassFactory({
    __init__  = function (self, ...)
        Pranaland:super().__init__(self, ...)
        self.animals = {slesandra = 1, chuchundra = 3, sisyandra = 1}
    end;
}, Location)
Shrinavas = ClassFactory({
    -- Добавляет 13 процентов к производительности чучундр
    affect_shlyamsanye = function (self, context)
        context.change:chain(Change(function(_self, ds)
            ds.health_delta = ds.health_delta + 1.13 * self.animals.chuchundra
        end))
    end;

    __str__ = function (self)
        return 'Pranaland, Shrinavas'
    end;
}, Pranaland)
KhareKirishi = ClassFactory({
    -- При попадании Дроцентов они расходуют дополнительно по 10% здоровья за каждый интервал
    affect_general = function (self, context)
        if context.nation:isinstance(Drotsent) then
            context.change:chain(Change(function(_self, ds)
                ds.health_delta = ds.health_delta * 1.1
            end))
        end
    end;

    __str__ = function (self)
        return 'Pranaland, KhareKirishi'
    end;
}, Pranaland)


Race = ClassFactory({
    affect_gulbonstvo = function (self, context)
        return
    end;

    affect_zumbalstvo = function (self, context)
        return
    end;

    affect_shlyamsanye = function (self, context)
        return
    end;

    affect_general = function (self, context)
        return
    end;
})

Shlendrik = ClassFactory({}, Race)
Mozhor = ClassFactory({
    -- Можоры. 
    -- При гульбонстве тратят на 23 процента больше денег по сравнению с остальными, 
    -- зато при зумбальстве в одном случае из 3 вообще не расходуют здоровье
    affect_gulbonstvo = function (self, context)
        context.change:chain(Change(function(_self, ds)
            ds.money_delta = ds.money_delta * 1.23
        end))
    end;

    affect_zumbalstvo = function (self, context)
        if roll_dice(0.33) then
            context.change:chain(Change(function(_self, ds)
                ds.health_delta = 0
            end))
        end
    end;

    __str__ = function (self)
        return 'Shlendrik, Mozhor'
    end;
}, Shlendrik)
Nishcheborod = ClassFactory({
    -- Нищебороды. 
    -- При гульбонстве тратят на 87 процентов меньше денег, но на 76 процентов больше здоровья
    affect_gulbonstvo = function (self, context)
        context.change:chain(Change(function(_self, ds)
            ds.money_delta = ds.money_delta * 0.87
            ds.health_delta = ds.health_delta * 1.76
        end))
    end;

    __str__ = function (self)
        return 'Shlendrik, Nishcheborod'
    end;
}, Shlendrik)

Hipstick = ClassFactory({}, Race)
Soyevyy = ClassFactory({
    -- Соевые. 
    -- Крайне тяжело переносят зумбальство, 
    -- затрачивая дополнительно 0.12 единиц здоровья на каждую чучундру в локации. 
    affect_zumbalstvo = function (self, context)
        context.change:chain(Change(function(_self, ds)
            ds.health_delta = ds.health_delta - 0.12 * context.area.animals.chuchundra
        end))
    end;

    __str__ = function (self)
        return 'Hipstick, Soyevyy'
    end;
}, Hipstick)
Prosvetlennyy = ClassFactory({
    -- Просветленные. 
    -- Во время шлямсания могут получить дополнтельную удовлетворенность жизнью в количестве, 
    -- равном количеству сисяндр в полследних 3 локациях, умноженному на 0.31
    affect_shlyamsanye = function (self, context)
        context.change:chain(Change(function(_self, ds)
            for i = 1, math.min(3, #context.previous_areas) do
                ds.satisfaction_delta = ds.satisfaction_delta + 0.31 * context.previous_areas[i].animals.sisyandra
            end
        end))
    end;

    __str__ = function (self)
        return 'Hipstick, Prosvetlennyy'
    end;
}, Hipstick)

Skufik = ClassFactory({}, Race)
Drotsent = ClassFactory({
    -- Дроценты. 
    -- Практически не умеют гульбонить, затрачивая вполовину меньше здоровья и денег, 
    -- и получая вполовину меньше удовлетворенности
    affect_gulbonstvo = function (self, context)
        context.change:chain(Change(function(_self, ds)
            ds.money_delta = ds.money_delta / 2
            ds.health_delta = ds.health_delta / 2
            ds.satisfaction_delta = ds.satisfaction_delta / 2
        end))
    end;

    __str__ = function (self)
        return 'Skufik, Drotsent'
    end;
}, Skufik)
Zheleznoukhiy = ClassFactory({
    -- Железноухие. 
    -- Не расходуют удовлетворенность жизнью при зумбальстве, 
    -- зато с вероятностью 0.33 не получают денег от каждой слесандры в локации
    affect_zumbalstvo = function (self, context)
        context.change:chain(Change(function(_self, ds)
            ds.satisfaction_delta = 0
        end))
        if roll_dice(0.33) then
            context.change:chain(Change(function(_self, ds)
                ds.money_delta = 0
            end))
        end
    end;

    __str__ = function (self)
        return 'Skufik, Zheleznoukhiy'
    end;
}, Skufik)


Durlyandets = ClassFactory({
    __init__ = function (self, health, money, satisfaction, area, areas)
        self.health = health
        self.money = money
        self.satisfaction = satisfaction

        self.area = area

        self.areas = areas
    end;

    __str__ = function (self)
        return 'Durlyandets(id=' .. string.format("%p", self) .. ',health=' .. self.health .. ',money=' .. self.money .. ',satisfaction=' .. self.satisfaction .. ')'
    end;

    do_zumbalstvo = function(self)
        print(tostring(self) .. ' doing zumbalstvo')
    end;

    do_gulbonstvo = function(self) 
        print(tostring(self) .. ' doing gulbonstvo')
    end;

    do_shlyamsanye = function(self)
        print(tostring(self) .. ' doing shlyamsanye')
    end;

    do_nothing = function(self) 
        print(tostring(self) .. ' doing nothing')
    end;

    choose_action = function (self)
        local actions = {
            self.do_zumbalstvo,
            self.do_gulbonstvo,
            self.do_shlyamsanye,
            self.do_nothing,
        }
        return actions[math.random(#actions)]
    end;

    move = function (self, new_area)
        if new_area ~= self.area then
            print(tostring(self) .. ' moving to area ' .. tostring(new_area))
            self.area = new_area
        end
    end;

    choose_area = function (self)
        local area = get_random_obj(self.areas)
        return area
    end;

    take_turn = function (self)
        local new_area = self:choose_area()
        self:move(new_area)
        local action = self:choose_action()
        action(self)
    end;

    is_alive = function (self)
        return self.health > 0 and self.money > 0 and self.satisfaction > 0
    end;

    is_dead = function (self)
        return not self:is_alive()
    end;
})

World = ClassFactory({
    __init__ = function (self)
        self.areas = {
            workland = {
                balbesburg = Balbesburg(),
                dolbesburg = Dolbesburg(),
            },
            beachland = {
                kuramariby = Kuramariby(),
                punta_pelikana = PuntaPelikana(),
            },
            pranaland = {
                shrinavas = Shrinavas(),
                khare_kirishi = KhareKirishi(),
            }
        }

        self.nations = {
            shlendrik = {
                mozhor = Mozhor(),
                nishcheborod = Nishcheborod(),
            },
            hipstick = {
                soyevyy = Soyevyy(),
                prosvetlennyy = Prosvetlennyy(),
            },
            skufik = {
                drotsent = Drotsent(),
                zheleznoukhiy = Zheleznoukhiy(),
            }
        }
        
        self.population = {
            durlyandets_1 = self:get_random_durlyandets(),
        }
    end;

    get_random_durlyandets = function (self)
        local nation = self:get_random_nation()
        local area = self:get_random_area()
        local obj = Durlyandets(10, 10, 10, area, self.areas)
        local durlyandets = {
            obj = obj,
            nation = nation,
            context = {
                durlyandets = obj,
                previous_areas = {},
                change = Change(),
                delta_state = DeltaState(),
                area = area,
                nation = nation,
            }
        }
        self:add_move_callback(durlyandets)
        self:add_action_callback(durlyandets, 'zumbalstvo')
        self:add_action_callback(durlyandets, 'gulbonstvo')
        self:add_action_callback(durlyandets, 'shlyamsanye')
        self:add_action_callback(durlyandets, 'nothing')
        print('Created ' .. tostring(durlyandets.obj) .. ' from nation ' .. tostring(nation))
        return durlyandets
    end;

    add_move_callback = function (self, durlyandets)
        durlyandets.obj['move'] = function (_self, new_area)
        
            table.insert(durlyandets.context.previous_areas, 1, durlyandets.context.area)
            durlyandets.context.area = new_area

            _self._cf_instance_class['move'](_self, new_area)
        end
    end;

    add_action_callback = function (self, durlyandets, action)
        local do_method_name = 'do_' .. action
        local affect_method_name = 'affect_' .. action
        durlyandets.obj[do_method_name] = function (_self, ...)
            
            if action ~= 'nothing' then
                durlyandets.context.area[affect_method_name](durlyandets.context.area, durlyandets.context)
                durlyandets.nation[affect_method_name](durlyandets.nation, durlyandets.context)
            else
                durlyandets.context.delta_state = DeltaState(-0.5)
            end;

            _self._cf_instance_class[do_method_name](_self, ...)
        end
    end;

    get_random_area = function (self)
        return get_random_obj(self.areas)
    end;

    get_random_nation = function (self)
        return get_random_obj(self.nations)
    end;

    next_iter = function (self)
        for idx, durlyandets in pairs(self.population) do
            durlyandets.context.delta_state = DeltaState(-1)
            durlyandets.context.change = Change()
            
            durlyandets.obj:take_turn()

            durlyandets.context.area:affect_general(durlyandets.context)
            durlyandets.nation:affect_general(durlyandets.context)
            
            durlyandets.context.change:apply(durlyandets.context.delta_state)

            -- print(durlyandets.context.delta_state)
            durlyandets.context.delta_state:apply(durlyandets.obj)

            if durlyandets.obj:is_dead() then
                print(tostring(durlyandets.obj) .. ' died')
                self.population[idx] = nil
            end
        end
    end

})
local world = World()
for i = 1, 25 do
    print('iter ' .. i)
    world:next_iter()
end
