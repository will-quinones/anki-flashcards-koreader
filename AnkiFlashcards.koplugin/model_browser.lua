-- Native model selector: explicit discovery, local AND search, explicit choice.
local Catalog = require("model_catalog")
local AI = require("ai_configuration")
local _ = require("gettext")
local Browser = {}
local instances = setmetatable({}, {__mode="k"})
local pending = {}
function Browser.cancel_all()
    local copy = {}; for state in pairs(pending) do copy[#copy+1]=state end
    for _, state in ipairs(copy) do state:cancel() end
end
function Browser.configuration_changed()
    for state in pairs(instances) do state:check_identity() end
end
function Browser.new(spec)
    local UI = require("ui/uimanager")
    local Info = require("ui/widget/infomessage")
    local state = {items={}, query="", identity=Catalog.identity(spec.config(),spec.provider)}
    instances[state]=true
    local function current() return spec.config()[spec.field.key] or spec.field.default end
    function state:cancel()
        self.generation=(self.generation or 0)+1
        if self.poll then UI:unschedule(self.poll); self.poll=nil end
        if self.job then self.job:cancel(UI); self.job=nil end
        pending[self]=nil
        if self.modal then local modal=self.modal; self.modal=nil; UI:close(modal) end
    end
    function state:check_identity()
        local identity = Catalog.identity(spec.config(),spec.provider)
        if identity ~= self.identity then
            self:cancel(); self.identity=identity; self.models=nil; self.query=""
            self:render()
        end
    end
    local function action(text, callback)
        return {text=text, keep_menu_open=true, callback=function(menu)
            state.menu=menu or state.menu
            callback()
        end}
    end
    function state:render()
        local items = self.items
        for i=#items,1,-1 do items[i]=nil end
        items[#items+1]=action(_("Escribir modelo…"),spec.edit)
        items[#items+1]=action(self.models and _("Actualizar catálogo del proveedor") or _("Cargar catálogo del proveedor"),function() self:load() end)
        if self.models then items[#items+1]=action(_("Usar lista incluida"),function() self.models=nil; self:render() end) end
        items[#items+1]=action(self.query == "" and _("Buscar modelos…") or _("Búsqueda: ") .. self.query,function() self:search() end)
        if self.query ~= "" then items[#items+1]=action(_("Mostrar todos los modelos"),function() self.query=""; self:render() end) end
        items[#items+1]={text_func=function() return _("Modelo actual: ") .. current() end, enabled=false}
        local models = self.models or AI.choices(spec.provider,spec.category,current(),spec.field.default)
        local matches = Catalog.filter(models,self.query)
        local label = self.models and _("Catálogo del proveedor: ") or _("Lista incluida: ")
        items[#items+1]={text=label .. #matches .. _(" de ") .. #models .. _(" modelos"),enabled=false}
        if #matches == 0 then items[#items+1]={text=_("Sin resultados. Cambia la búsqueda o escribe el modelo."),enabled=false} end
        -- An active custom ID stays visible even if the refreshed catalog omits
        -- it. Search never selects this or any other result automatically.
        if self.models and self.query == "" then
            local found=false; for _, id in ipairs(models) do if id==current() then found=true; break end end
            if not found then local list={current()}; for _,id in ipairs(matches) do list[#list+1]=id end; matches=list end
        end
        for _i, id in ipairs(matches) do
            local value=id
            local item=action(value .. (value == spec.field.default and _(" (predeterminado)") or ""),function()
                if spec.select(value) then self:render() end
            end)
            item.checked_func=function() return current()==value end
            items[#items+1]=item
        end
        if self.menu and self.menu.item_table == items then self.menu:updateItems(1) end
    end
    function state:search()
        local Input = require("ui/widget/inputdialog")
        local dialog
        dialog=Input:new {title=_("Buscar modelos · ") .. spec.name, input=self.query,
            input_hint=_("Ejemplo: gemini flash o :free"),
            buttons={{
                {text=_("Cancelar"),callback=function() UI:close(dialog) end},
                {text=_("Buscar"),is_enter_default=true,callback=function()
                    self.query=(dialog:getInputText() or ""):sub(1,200):match("^%s*(.-)%s*$")
                    UI:close(dialog); self:render()
                end},
            }}}
        UI:show(dialog); dialog:onShowKeyboard()
    end
    function state:load()
        self:check_identity(); self:cancel()
        local cfg=spec.config()
        if not require("settings_state").has_key(Catalog.key(cfg,spec.provider)) then
            UI:show(Info:new {text=_("Añade primero la clave API de este proveedor.")}); return
        end
        local job, err = Catalog.launch(cfg,spec.provider,spec.category)
        if not job then UI:show(Info:new {text=err}); return end
        self.job=job; pending[self]=true
        local generation=self.generation
        self.modal=Info:new {text=_("Consultando modelos de ") .. spec.name .. _("…\nToca para cancelar."),
            dismiss_callback=function() self:cancel() end}
        UI:show(self.modal)
        self.poll=function()
            if self.generation ~= generation then return end
            if Catalog.identity(spec.config(),spec.provider) ~= self.identity then self:check_identity(); return end
            local result=job:poll(UI)
            if not result then UI:scheduleIn(0.2,self.poll); return end
            self.job=nil
            self:cancel()
            if result.models then
                self.models=result.models; self:render()
                if #result.models==0 then UI:show(Info:new {text=_("El proveedor no devolvió modelos compatibles. Puedes escribir el modelo o usar la lista incluida.")}) end
            else
                UI:show(Info:new {text=result.error or _("No se pudo cargar el catálogo.")})
            end
        end
        UI:scheduleIn(0.2,self.poll)
    end
    state:render()
    return state
end
return Browser
