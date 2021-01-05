﻿unit Delphi.Rest.Server.Service.Component;

interface

uses System.Classes, System.SysUtils, System.Rtti, Web.HTTPApp, Delphi.Rest.Service.Container, Delphi.Rest.JSON.Serializer;

type
  EInvalidParameterType = class(Exception);
  TOnGetServiceContainer = function: IServiceContainer of object;

  TRestServerService = class(TComponent, IGetWebAppServices, IWebAppServices, IWebExceptionHandler)
  private
    FActive: Boolean;
    FRequest: TWebRequest;
    FResponse: TWebResponse;
    FServiceContainer: IServiceContainer;
    FSerializer: TRestJsonSerializer;
    FOnGetServiceContainer: TOnGetServiceContainer;

    function GetParams(Info: TRttiMethod; var ConvertedParams: TArray<TValue>): Boolean;
    function GetParamValue(Param: TRttiParameter; const Value: String): TValue;
    function GetSerializer: TRestJsonSerializer;
    function GetServiceContainer: IServiceContainer;

    procedure SortQueryFields;

    // IGetWebAppServices
    function GetWebAppServices: IWebAppServices;

    // IWebAppServices
    function GetActive: Boolean;
    function GetExceptionHandler: TObject;
    function HandleRequest: Boolean;

    procedure FinishContext;
    procedure InitContext(WebModule: TComponent; Request: TWebRequest; Response: TWebResponse);

    // IWebExceptionHandler
    procedure HandleException(E: Exception; var Handled: Boolean);

    property Serializer: TRestJsonSerializer read GetSerializer;
  public
    destructor Destroy; override;

    property Request: TWebRequest read FRequest;
    property Response: TWebResponse read FResponse;
    property ServiceContainer: IServiceContainer read GetServiceContainer write FServiceContainer;
  published
    property Active: Boolean read FActive write FActive;
    property OnGetServiceContainer: TOnGetServiceContainer read FOnGetServiceContainer write FOnGetServiceContainer;
  end;

implementation

uses System.TypInfo, System.Math, Winapi.WinInet, REST.Types{$IFDEF DCC}, System.JSON.Serializers{$ENDIF};

{ TRestServerService }

destructor TRestServerService.Destroy;
begin
  FSerializer.Free;

  inherited;
end;

procedure TRestServerService.FinishContext;
begin

end;

function TRestServerService.GetActive: Boolean;
begin
  Result := FActive;
end;

function TRestServerService.GetExceptionHandler: TObject;
begin
  Result := Self;
end;

function TRestServerService.GetParams(Info: TRttiMethod; var ConvertedParams: TArray<TValue>): Boolean;
begin
  ConvertedParams := [];
  var Parameters := Info.GetParameters;
  Result := Length(Parameters) = Request.QueryFields.Count;

  SortQueryFields;

  if Result then
    for var Param in Parameters do
      ConvertedParams := ConvertedParams + [GetParamValue(Param, Request.QueryFields.Values[Param.Name])];
end;

function TRestServerService.GetParamValue(Param: TRttiParameter; const Value: String): TValue;
begin
  case Param.ParamType.TypeKind of
    tkClassRef,
    tkInterface,
    tkMethod,
    tkPointer,
    tkProcedure,
    tkUnknown,
    tkVariant: raise EInvalidParameterType.Create('The param type is invalid!');
    else Result := FSerializer.Deserialize(Value, Param.ParamType.Handle);
  end;
end;

function TRestServerService.GetSerializer: TRestJsonSerializer;
begin
  if not Assigned(FSerializer) then
    FSerializer := TRestJsonSerializer.Create;

  Result := FSerializer;
end;

function TRestServerService.GetServiceContainer: IServiceContainer;
begin
  if not Assigned(FServiceContainer) and Assigned(FOnGetServiceContainer) then
    FServiceContainer := FOnGetServiceContainer;

  Result := FServiceContainer;
end;

function TRestServerService.GetWebAppServices: IWebAppServices;
begin
  Result := Self;
end;

procedure TRestServerService.HandleException(E: Exception; var Handled: Boolean);
begin
  Handled := True;
  Response.Content := E.Message;
  Response.StatusCode := HTTP_STATUS_SERVER_ERROR;

  Response.SendResponse;
end;

function TRestServerService.HandleRequest: Boolean;
begin
  var URL := Request.URL;

  Result := ExtractFileExt(URL).IsEmpty;

  if Result then
  begin
    var Info: TRttiType := nil;
    var Instance := TValue.Empty;
    var Params := URL.Split(['/'], TStringSplitOptions.ExcludeEmpty);

    Result := (Length(Params) > 0) and ServiceContainer.GetService(Params[0], Info, Instance);

    if Result then
      if Length(Params) = 2 then
      begin
        var Method := Info.GetMethod(Params[1]);

        if Assigned(Method) then
        begin
          var ProcParams: TArray<TValue>;

          if GetParams(Method, ProcParams) then
          begin
            var Return := Method.Invoke(Instance, ProcParams);

            if Assigned(Method.ReturnType) then
            begin
              Response.Content := Serializer.Serialize(Return);
              Response.ContentType := CONTENTTYPE_APPLICATION_JSON;
            end;

            Response.StatusCode := HTTP_STATUS_OK;
          end
          else
            Response.StatusCode := HTTP_STATUS_BAD_REQUEST;
        end
        else
          Response.StatusCode := HTTP_STATUS_NOT_FOUND;
      end
      else
        Response.StatusCode := HTTP_STATUS_NOT_FOUND;
  end;
end;

procedure TRestServerService.InitContext(WebModule: TComponent; Request: TWebRequest; Response: TWebResponse);
begin
  FRequest := Request;
  FResponse := Response;
end;

procedure TRestServerService.SortQueryFields;
begin
  TStringList(Request.QueryFields).Sorted := True;
end;

end.

